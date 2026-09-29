require "test_helper"

class Settings::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    Resolv.stubs(:getaddresses).returns([ "203.0.113.10" ])
  end

  test "show" do
    get settings_notifications_url
    assert_response :success
    assert_select "input[name='bill_reminder_webhook[url]']"
  end

  test "members opt in to reminder emails themselves" do
    patch settings_notifications_url, params: { user: { bill_reminder_emails: "1" } }

    assert_redirected_to settings_notifications_url
    assert @user.reload.bill_reminder_emails?
  end

  test "admins set up the push channel and the token is never echoed back" do
    patch webhook_settings_notifications_url, params: {
      bill_reminder_webhook: { url: "https://ntfy.example.com/bills", payload_format: "ntfy", token: "tk_secret", enabled: "1" }
    }

    webhook = @user.family.reload.bill_reminder_webhook
    assert_equal [ "https://ntfy.example.com/bills", "tk_secret", @user ], [ webhook.url, webhook.token, webhook.user ]

    get settings_notifications_url
    assert_not_includes response.body, "tk_secret"

    # A blank token on a later save keeps the stored one.
    patch webhook_settings_notifications_url, params: { bill_reminder_webhook: { url: "https://ntfy.example.com/rent", token: "" } }
    assert_equal "tk_secret", webhook.reload.token
  end

  test "a refused URL re-renders with the reason" do
    Resolv.stubs(:getaddresses).returns([ "169.254.169.254" ])

    patch webhook_settings_notifications_url, params: { bill_reminder_webhook: { url: "http://metadata.example/x", payload_format: "json" } }

    assert_response :unprocessable_entity
    assert_nil @user.family.reload.bill_reminder_webhook
  end

  test "members cannot change the family push channel" do
    sign_in users(:family_member)

    patch webhook_settings_notifications_url, params: { bill_reminder_webhook: { url: "https://ntfy.example.com/bills" } }

    assert_redirected_to settings_notifications_url
    assert_nil families(:dylan_family).reload.bill_reminder_webhook
  end

  test "test send reports a failure" do
    @user.family.create_bill_reminder_webhook!(user: @user, url: "https://ntfy.example.com/bills")
    stub_request(:post, "https://ntfy.example.com/").to_return(status: 403)

    post test_webhook_settings_notifications_url

    assert_redirected_to settings_notifications_url
    assert_equal I18n.t("settings.notifications.test_webhook.failure", error: "HTTP 403"), flash[:alert]
  end

  test "removing the push channel" do
    @user.family.create_bill_reminder_webhook!(user: @user, url: "https://ntfy.example.com/bills")

    delete webhook_settings_notifications_url

    assert_nil @user.family.reload.bill_reminder_webhook
  end
end
