class Settings::NotificationsController < ApplicationController
  layout "settings"

  before_action :require_admin!, only: %i[update_webhook destroy_webhook test_webhook]

  def show
    @user = Current.user
    @webhook = Current.family.bill_reminder_webhook || Current.family.build_bill_reminder_webhook(payload_format: "ntfy")
  end

  # The member's own email opt-in.
  def update
    user = Current.user
    user.transaction do
      user.lock!
      preferences = (user.preferences || {}).deep_dup
      preferences["bill_reminder_emails"] = params.dig(:user, :bill_reminder_emails) == "1"
      user.update!(preferences: preferences)
    end

    redirect_to settings_notifications_path, notice: t(".success")
  end

  # The family's push channel. A blank token keeps the stored one, so the secret is
  # never sent back to the browser to be re-submitted.
  def update_webhook
    @user = Current.user
    @webhook = Current.family.bill_reminder_webhook || Current.family.build_bill_reminder_webhook
    attributes = webhook_params
    attributes.delete(:token) if attributes[:token].blank?
    @webhook.assign_attributes(attributes.merge(user: Current.user))

    if @webhook.save
      redirect_to settings_notifications_path, notice: t(".success")
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy_webhook
    Current.family.bill_reminder_webhook&.destroy!
    redirect_to settings_notifications_path, notice: t(".success")
  end

  def test_webhook
    webhook = Current.family.bill_reminder_webhook
    return redirect_to(settings_notifications_path, alert: t(".not_configured")) unless webhook

    webhook.send_test
    redirect_to settings_notifications_path, notice: t(".success")
  rescue BillReminderWebhook::DeliveryError => e
    redirect_to settings_notifications_path, alert: t(".failure", error: e.message)
  end

  private
    def webhook_params
      params.require(:bill_reminder_webhook).permit(:url, :token, :payload_format, :enabled)
    end

    def require_admin!
      redirect_to settings_notifications_path, alert: t("settings.notifications.admin_only") unless Current.user.admin?
    end
end
