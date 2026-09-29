require "test_helper"

class BillReminderMailerTest < ActionMailer::TestCase
  test "digest lists the claimed bills with amounts and a link" do
    series = recurring_transactions(:netflix_subscription)
    occurrence = series.recurring_occurrences.create!(family: series.family, original_due_on: Date.current - 5,
                                                      due_on: Date.current - 5, currency: "USD")
    user = users(:family_admin)

    email = BillReminderMailer.with(user: user, reminders: [ [ occurrence.id, "overdue" ] ]).digest

    assert_emails(1) { email.deliver_now }
    assert_equal [ user.email ], email.to
    assert_equal "1 bill overdue", email.subject
    assert_includes email.text_part.body.to_s, "Overdue: Netflix: $15.99"
    assert_includes email.html_part.body.to_s, "/bills"
  end
end
