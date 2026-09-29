class BillReminderMailer < ApplicationMailer
  # params: user:, reminders: [[recurring_occurrence_id, kind], ...] as claimed by BillReminder.
  def digest
    @user = params[:user]
    family = @user.family
    kinds = params[:reminders].to_h

    occurrences = family.recurring_occurrences.where(id: kinds.keys).includes(recurring_transaction: %i[merchant account])
    items = occurrences.map { |occurrence| BillReminder::Item.new(occurrence: occurrence, kind: kinds[occurrence.id]) }
    return if items.empty?

    @message = BillReminder::Message.new(family, items)

    I18n.with_locale(@user.locale.presence || family.locale) do
      mail(to: @user.email, subject: @message.title)
    end
  end
end
