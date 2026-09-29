# Ledger of bill reminders already sent, so an hourly run never repeats one. A row is
# claimed before sending (race-safe: the unique index decides which run sends) and
# released again when the channel fails, so the next run retries.
class BillReminderDelivery < ApplicationRecord
  belongs_to :recurring_occurrence

  KINDS = %w[due_soon overdue].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :due_on, :channel, presence: true

  # Returns the subset of +items+ (BillReminder::Item) this call claimed for +channel+.
  def self.claim(items, channel:)
    return [] if items.empty?

    now = Time.current
    rows = items.map do |item|
      { recurring_occurrence_id: item.occurrence.id, kind: item.kind, due_on: item.due_on,
        channel: channel, created_at: now, updated_at: now }
    end

    claimed = insert_all(rows, unique_by: :index_bill_reminder_deliveries_uniqueness,
                               returning: %i[recurring_occurrence_id kind]).rows.to_set

    items.select { |item| claimed.include?([ item.occurrence.id, item.kind ]) }
  end

  def self.release(items, channel:)
    items.each do |item|
      where(recurring_occurrence_id: item.occurrence.id, kind: item.kind, due_on: item.due_on, channel: channel).delete_all
    end
  end
end
