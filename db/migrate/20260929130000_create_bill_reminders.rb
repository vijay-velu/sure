class CreateBillReminders < ActiveRecord::Migration[8.1]
  def change
    # One push endpoint per family (ntfy topic, Gotify, or any JSON webhook). The URL and
    # token are secrets: they are encrypted at rest when Active Record encryption is set.
    create_table :bill_reminder_webhooks, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }
      # Whose account access decides which bills the family-wide channel may mention.
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.text :url, null: false
      t.text :token
      t.string :payload_format, null: false, default: "ntfy"
      t.boolean :enabled, null: false, default: true
      t.datetime :last_delivered_at
      t.string :last_error
      t.timestamps
    end
    add_check_constraint :bill_reminder_webhooks, "payload_format IN ('ntfy', 'json')", name: "chk_bill_reminder_webhooks_payload_format"

    # Ledger of reminders sent: one per occurrence, reminder kind, due date and channel. The
    # due date is part of the key so snoozing a bill re-arms its reminder.
    create_table :bill_reminder_deliveries, id: :uuid do |t|
      t.references :recurring_occurrence, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.string :kind, null: false
      t.date :due_on, null: false
      t.string :channel, null: false
      t.timestamps
    end
    add_index :bill_reminder_deliveries, %i[recurring_occurrence_id kind due_on channel],
              unique: true, name: "index_bill_reminder_deliveries_uniqueness"
  end
end
