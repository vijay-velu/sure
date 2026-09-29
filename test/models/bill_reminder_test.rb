require "test_helper"

class BillReminderTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @family = families(:dylan_family)
    @family.update!(timezone: "Asia/Kolkata")
    @series = recurring_transactions(:netflix_subscription) # on the depository account, shared with the member
    @admin = users(:family_admin)
    @member = users(:family_member)
  end

  test "bills in their reminder window and freshly overdue bills are reminded" do
    travel_to Time.zone.parse("2026-09-29 10:00 +05:30") do
      due_soon = occurrence(due_on: Date.current + 2)
      occurrence(due_on: Date.current + 10) # still upcoming
      overdue = occurrence(due_on: Date.current - 5)
      occurrence(due_on: Date.current - 40) # overdue too long to announce
      paid = occurrence(due_on: Date.current + 1)
      paid.close!("paid", source: "user")

      items = BillReminder.new(@family).items

      assert_equal [ [ overdue, "overdue" ], [ due_soon, "due_soon" ] ], items.map { |item| [ item.occurrence, item.kind ] }
    end
  end

  test "the bill's own reminder days widen its window" do
    @series.update!(notify_days_before: 10)

    travel_to Time.zone.parse("2026-09-29 10:00 +05:30") do
      reminded = occurrence(due_on: Date.current + 9)
      assert_equal [ reminded ], BillReminder.new(@family).items.map(&:occurrence)
    end
  end

  test "income is never reminded" do
    income = @family.recurring_transactions.create!(
      name: "Salary", amount: -100_000, currency: "USD", bill_type: "income",
      expected_day_of_month: 1, last_occurrence_date: Date.current, next_expected_date: Date.current, status: "active"
    )
    income.recurring_occurrences.delete_all
    income.recurring_occurrences.create!(family: @family, original_due_on: Date.current + 1, due_on: Date.current + 1, currency: "USD")

    assert_empty BillReminder.new(@family).items.select { |item| item.series == income }
  end

  test "emails each opted-in member once, only about bills they can see" do
    private_series = @family.recurring_transactions.create!(
      name: "Broker fee", amount: 500, currency: "USD", account: accounts(:investment),
      expected_day_of_month: 1, last_occurrence_date: Date.current, next_expected_date: Date.current, status: "active"
    )
    private_series.recurring_occurrences.delete_all
    opt_in(@admin, @member)

    travel_to Time.zone.parse("2026-09-29 10:00 +05:30") do
      shared = occurrence(due_on: Date.current + 1)
      hidden = private_series.recurring_occurrences.create!(family: @family, original_due_on: Date.current + 1,
                                                            due_on: Date.current + 1, currency: "USD")

      assert_enqueued_emails 2 do
        BillReminder.new(@family).deliver
      end

      assert_equal [ shared.id, hidden.id ].sort, channel_occurrences("email:#{@admin.id}").sort
      assert_equal [ shared.id ], channel_occurrences("email:#{@member.id}")

      assert_no_enqueued_emails { BillReminder.new(@family).deliver }
    end
  end

  test "sends nothing at night in the family's time zone" do
    opt_in(@admin)

    travel_to Time.zone.parse("2026-09-29 23:30 +05:30") do
      occurrence(due_on: Date.current + 1)

      assert_no_enqueued_emails { BillReminder.new(@family).deliver }
      assert_enqueued_emails(1) { BillReminder.new(@family).deliver(force: true) }
    end
  end

  test "snoozing re-arms the reminder for the new date" do
    opt_in(@admin)

    travel_to Time.zone.parse("2026-09-29 10:00 +05:30") do
      bill = occurrence(due_on: Date.current + 1)
      assert_enqueued_emails(1) { BillReminder.new(@family).deliver }

      bill.snooze!(Date.current + 2)
      assert_enqueued_emails(1) { BillReminder.new(@family).deliver }
    end
  end

  test "a failed push is released so the next run retries it" do
    stub_resolve
    webhook = @family.create_bill_reminder_webhook!(user: @admin, url: "https://ntfy.example.com/bills", payload_format: "ntfy")
    stub_request(:post, "https://ntfy.example.com/").to_return(status: 502)

    travel_to Time.zone.parse("2026-09-29 10:00 +05:30") do
      occurrence(due_on: Date.current + 1)
      BillReminder.new(@family).deliver
    end

    assert_empty channel_occurrences("webhook")
    assert_equal "HTTP 502", webhook.reload.last_error
  end

  test "a delivered push is recorded and names the bill" do
    stub_resolve
    webhook = @family.create_bill_reminder_webhook!(user: @admin, url: "https://ntfy.example.com/bills", payload_format: "ntfy")
    request = stub_request(:post, "https://ntfy.example.com/")
                .with { |req| JSON.parse(req.body).values_at("topic", "priority") == [ "bills", 3 ] && req.body.include?("Netflix") }
                .to_return(status: 200)

    travel_to Time.zone.parse("2026-09-29 10:00 +05:30") do
      bill = occurrence(due_on: Date.current + 1)
      BillReminder.new(@family).deliver

      assert_requested request
      assert_equal [ bill.id ], channel_occurrences("webhook")
      assert_not_nil webhook.reload.last_delivered_at
    end
  end

  private
    def occurrence(due_on:)
      @series.recurring_occurrences.create!(family: @family, original_due_on: due_on, due_on: due_on, currency: "USD")
    end

    def opt_in(*users)
      users.each { |user| user.update!(preferences: (user.preferences || {}).merge("bill_reminder_emails" => true)) }
    end

    def channel_occurrences(channel)
      BillReminderDelivery.where(channel: channel).pluck(:recurring_occurrence_id)
    end

    def stub_resolve
      Resolv.stubs(:getaddresses).with("ntfy.example.com").returns([ "203.0.113.10" ])
    end
end
