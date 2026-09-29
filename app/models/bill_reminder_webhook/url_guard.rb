require "ipaddr"
require "resolv"

# Decides whether a reminder webhook URL may be called, and which address to connect
# to. The address is resolved once and the connection is pinned to it, so a DNS answer
# that changes between the check and the request cannot redirect it.
#
# Cloud metadata and link-local addresses are always refused. Private ranges (LAN,
# loopback, CGNAT/Tailscale) are allowed only on a self-hosted install, where a push
# server on the same network is the normal setup; a managed install refuses them.
class BillReminderWebhook::UrlGuard
  class Blocked < StandardError; end

  Target = Data.define(:uri, :ip)

  ALWAYS_BLOCKED = %w[
    0.0.0.0/8 169.254.0.0/16 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32
    ::/128 fe80::/10 ff00::/8 fd00:ec2::254/128
  ].map { |range| IPAddr.new(range) }.freeze

  PRIVATE = %w[
    10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 100.64.0.0/10
    ::1/128 fc00::/7
  ].map { |range| IPAddr.new(range) }.freeze

  def self.check!(url, allow_private: Rails.application.config.app_mode.self_hosted?, resolver: Resolv)
    uri = URI.parse(url.to_s)
    raise Blocked, "must be an http(s) URL" unless uri.is_a?(URI::HTTP) && uri.host.present?
    raise Blocked, "must not contain credentials" if uri.userinfo.present?

    addresses = resolver.getaddresses(uri.hostname)
    raise Blocked, "host does not resolve" if addresses.empty?

    ips = addresses.map { |address| IPAddr.new(address) }
    ips.each do |ip|
      ip = ip.native if ip.ipv4_mapped?
      raise Blocked, "address #{ip} is not allowed" if ALWAYS_BLOCKED.any? { |range| range.include?(ip) }
      raise Blocked, "private address #{ip} is only allowed when self-hosted" if !allow_private && PRIVATE.any? { |range| range.include?(ip) }
    end

    Target.new(uri: uri, ip: ips.first.to_s)
  rescue URI::InvalidURIError, IPAddr::InvalidAddressError
    raise Blocked, "invalid URL"
  end
end
