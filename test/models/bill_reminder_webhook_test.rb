require "test_helper"

class BillReminderWebhookTest < ActiveSupport::TestCase
  Guard = BillReminderWebhook::UrlGuard

  setup do
    @family = families(:dylan_family)
    @admin = users(:family_admin)
  end

  test "cloud metadata and link-local addresses are always refused" do
    resolver = stub(getaddresses: [ "169.254.169.254" ])

    error = assert_raises(Guard::Blocked) { Guard.check!("http://metadata.internal/latest", allow_private: true, resolver: resolver) }
    assert_match "not allowed", error.message
  end

  test "LAN addresses are allowed only when self-hosted" do
    resolver = stub(getaddresses: [ "192.168.1.20" ])

    assert_equal "192.168.1.20", Guard.check!("http://ntfy.lan/bills", allow_private: true, resolver: resolver).ip
    assert_raises(Guard::Blocked) { Guard.check!("http://ntfy.lan/bills", allow_private: false, resolver: resolver) }
  end

  test "IPv4-mapped IPv6 cannot smuggle a blocked address" do
    resolver = stub(getaddresses: [ "::ffff:169.254.169.254" ])

    assert_raises(Guard::Blocked) { Guard.check!("http://evil.example/", allow_private: true, resolver: resolver) }
  end

  test "only plain http(s) URLs without credentials are accepted" do
    resolver = stub(getaddresses: [ "203.0.113.10" ])

    [ "ftp://ntfy.example.com/bills", "javascript:alert(1)", "https://user:pass@ntfy.example.com/bills", "not a url" ].each do |url|
      assert_raises(Guard::Blocked, url) { Guard.check!(url, allow_private: true, resolver: resolver) }
    end
  end

  test "an ntfy URL must name a topic" do
    Resolv.stubs(:getaddresses).returns([ "203.0.113.10" ])
    webhook = @family.build_bill_reminder_webhook(user: @admin, url: "https://ntfy.example.com", payload_format: "ntfy")

    assert_not webhook.valid?
    assert webhook.errors.of_kind?(:url, :invalid)
  end

  test "json webhooks POST the digest with the token as a bearer credential" do
    Resolv.stubs(:getaddresses).returns([ "203.0.113.10" ])
    webhook = @family.create_bill_reminder_webhook!(user: @admin, url: "https://gotify.example.com/message",
                                                   payload_format: "json", token: "app-token")
    request = stub_request(:post, "https://gotify.example.com/message")
                .with(headers: { "Authorization" => "Bearer app-token", "Content-Type" => "application/json" }) do |req|
                  JSON.parse(req.body).slice("title", "priority") == { "title" => "Sure bill reminders", "priority" => 5 }
                end
                .to_return(status: 200)

    webhook.send_test

    assert_requested request
  end

  test "a blank token is stored as no token" do
    Resolv.stubs(:getaddresses).returns([ "203.0.113.10" ])
    webhook = @family.create_bill_reminder_webhook!(user: @admin, url: "https://ntfy.example.com/bills", token: "tk_secret")

    webhook.update!(token: "  ")
    assert_nil webhook.reload.token
  end
end
