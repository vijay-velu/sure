# Tells a family about bills that are coming due or have gone overdue.
#
# Sure already derives each open occurrence's state (upcoming, due, overdue) from the
# bill's own "remind me N days before" and grace days; this turns the transitions into
# messages. Each reminder is sent once per occurrence, state, due date and channel (see
# BillReminderDelivery), in one digest per channel:
#
#   - email, to each member who opted in, listing only bills on accounts they can see
#   - the family's push webhook (ntfy, Gotify or JSON), listing the bills visible to the
#     admin who set it up
#
# Runs hourly and only sends during the family's waking hours, in its own time zone.
class BillReminder
  Item = Data.define(:occurrence, :kind) do
    def series = occurrence.recurring_transaction
    def due_on = occurrence.effective_due_on
    def overdue? = kind == "overdue"
  end

  SEND_HOURS = 8..21
  # A bill's reminder window is at most this far ahead; notify_days_before is capped to it.
  MAX_NOTIFY_DAYS = 31
  # Overdue bills older than this are not announced (e.g. history just after enabling).
  OVERDUE_LOOKBACK_DAYS = 7

  attr_reader :family

  def self.deliver_all
    today = Date.current
    family_ids = RecurringOccurrence.open_status
                                    .where(due_on: (today - 60)..(today + MAX_NOTIFY_DAYS + 1))
                                    .distinct.pluck(:family_id)

    Family.where(id: family_ids).find_each do |family|
      new(family).deliver
    rescue StandardError => e
      Rails.error.report(e, context: { family_id: family.id })
    end
  end

  def initialize(family)
    @family = family
  end

  def deliver(force: false)
    in_family_zone do
      return unless force || Time.current.hour.in?(SEND_HOURS)

      pending = items
      return if pending.empty?

      deliver_webhook(pending)
      deliver_emails(pending)
    end
  end

  # Open occurrences of payable bills that are in their reminder window or overdue.
  def items
    in_family_zone do
      today = Date.current

      family.recurring_occurrences
            .open_status
            .joins(:recurring_transaction).merge(RecurringTransaction.payable)
            .where(due_on: ..(today + MAX_NOTIFY_DAYS))
            .where("recurring_occurrences.due_on >= :from OR recurring_occurrences.snoozed_until >= :from",
                   from: today - OVERDUE_LOOKBACK_DAYS - RecurringOccurrence::DEFAULT_GRACE_DAYS - 30)
            .includes(recurring_transaction: %i[merchant account])
            .order(:due_on)
            .filter_map { |occurrence| item_for(occurrence, today) }
    end
  end

  # Items whose accounts +user+ may see. A bill with no account belongs to the family.
  def visible_to(user, pending)
    account_ids = user.accessible_accounts.pluck(:id).to_set

    pending.select do |item|
      [ item.series.account_id, item.series.destination_account_id ].compact.all? { |id| account_ids.include?(id) }
    end
  end

  private
    def item_for(occurrence, today)
      kind = { due: "due_soon", overdue: "overdue" }[occurrence.derived_state]
      return unless kind
      return if kind == "overdue" && occurrence.effective_due_on < today - grace_days(occurrence) - OVERDUE_LOOKBACK_DAYS

      Item.new(occurrence: occurrence, kind: kind)
    end

    def grace_days(occurrence)
      occurrence.recurring_transaction.overdue_grace_days || RecurringOccurrence::DEFAULT_GRACE_DAYS
    end

    def deliver_webhook(pending)
      webhook = family.bill_reminder_webhook
      # The channel speaks with its creator's visibility; a deactivated creator stops it.
      return unless webhook&.enabled? && webhook.user.active?

      claimed = BillReminderDelivery.claim(visible_to(webhook.user, pending), channel: "webhook")
      return if claimed.empty?

      begin
        webhook.deliver(Message.new(family, claimed))
      rescue BillReminderWebhook::DeliveryError
        BillReminderDelivery.release(claimed, channel: "webhook")
      end
    end

    def deliver_emails(pending)
      family.users.where(active: true).find_each do |user|
        next unless user.bill_reminder_emails?

        claimed = BillReminderDelivery.claim(visible_to(user, pending), channel: "email:#{user.id}")
        next if claimed.empty?

        BillReminderMailer.with(user: user, reminders: claimed.map { |item| [ item.occurrence.id, item.kind ] })
                          .digest.deliver_later
      end
    end

    def in_family_zone(&)
      Time.use_zone(family.timezone.presence || Time.zone, &)
    end
end
