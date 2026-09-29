require "net/http"

# A family's push channel for bill reminders.
#
#   ntfy: https://ntfy.example.com/<topic>, optional access token (tk_...). Published with
#         ntfy's JSON API so titles and amounts (₹) survive intact.
#   json: any endpoint taking a JSON POST ({ title, message, priority, url, bills }), which
#         is Gotify's /message format; the token is sent as a Bearer header.
#
# Redirects are not followed and the connection is pinned to the address the URL guard
# checked. The token and URL are encrypted at rest when Active Record encryption is set.
class BillReminderWebhook < ApplicationRecord
  include Encryptable

  class DeliveryError < StandardError; end

  if encryption_ready?
    encrypts :url
    encrypts :token
  end

  TIMEOUT = 5

  belongs_to :family
  belongs_to :user

  enum :payload_format, { ntfy: "ntfy", json: "json" }, validate: true

  normalizes :url, with: ->(url) { url.to_s.strip }
  normalizes :token, with: ->(token) { token.to_s.strip.presence }

  validates :url, presence: true, length: { maximum: 2048 }
  validates :token, length: { maximum: 512 }
  validate :url_is_allowed, if: :url_changed?
  validate :ntfy_url_names_a_topic, if: :ntfy?

  def deliver(message)
    target = UrlGuard.check!(url)
    request_uri, payload = ntfy? ? ntfy_request(target.uri, message) : [ target.uri, json_payload(message) ]

    response = post(request_uri, target.ip, payload)
    raise DeliveryError, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    update_columns(last_delivered_at: Time.current, last_error: nil)
    true
  rescue UrlGuard::Blocked, DeliveryError, Timeout::Error, SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
    update_columns(last_error: e.message.to_s.truncate(250))
    raise DeliveryError, e.message
  end

  def send_test
    deliver(TestMessage.new(family))
  end

  # What a test send says, in the shape of a real digest.
  class TestMessage < BillReminder::Message
    def initialize(family)
      super(family, [])
    end

    def title = I18n.with_locale(family.locale) { I18n.t("bill_reminders.message.test_title") }
    def body = I18n.with_locale(family.locale) { I18n.t("bill_reminders.message.test_body") }
    def urgent? = false
  end

  private
    # ntfy's JSON API is POSTed to the server root with the topic in the body.
    def ntfy_request(uri, message)
      segments = uri.path.split("/").reject(&:empty?)
      topic = segments.pop
      base = uri.dup
      base.path = segments.empty? ? "/" : "/#{segments.join('/')}/"
      base.query = nil

      payload = {
        topic: topic,
        title: message.title,
        message: message.body,
        priority: message.urgent? ? 4 : 3,
        tags: [ message.urgent? ? "warning" : "calendar" ],
        click: message.url
      }
      [ base, payload ]
    end

    def json_payload(message)
      message.as_json.merge(priority: message.urgent? ? 8 : 5)
    end

    def post(uri, ip, payload)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = ip
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.write_timeout = TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{token}" if token.present?
      request.body = payload.to_json

      http.start { |connection| connection.request(request) }
    end

    def url_is_allowed
      UrlGuard.check!(url)
    rescue UrlGuard::Blocked => e
      errors.add(:url, :invalid, message: e.message)
    end

    def ntfy_url_names_a_topic
      path = URI.parse(url.to_s).path.to_s
      errors.add(:url, :invalid, message: "must end with the ntfy topic") if path.split("/").reject(&:empty?).empty?
    rescue URI::InvalidURIError
      nil
    end
end
