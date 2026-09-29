class BillRemindersJob < ApplicationJob
  queue_as :scheduled

  def perform
    BillReminder.deliver_all
  end
end
