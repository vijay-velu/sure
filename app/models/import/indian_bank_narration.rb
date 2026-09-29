# Turns the narration an Indian bank prints for a transaction into a readable name.
#
# Statement exports describe a payment as one string packed with routing data:
#
#   UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-512345678901-PAYMENT FROM PHONE          (HDFC)
#   TO TRANSFER-UPI/DR/512345678901/SWIGGY/YESB/swiggy@ybl/Pay--                (SBI)
#   NEFT CR-SBIN0001234-ACME CORP PVT LTD-SALARY SEP-N123456789012
#
# The counterparty is the one token that is not a channel word, reference number, IFSC,
# bank code, masked account, UPI handle or bank name. That becomes the name; the full
# narration is kept as notes so nothing is lost and rules can still match on it. A shape
# not recognised here is returned as it came.
class Import::IndianBankNarration
  Parsed = Data.define(:name, :notes)

  CHANNEL = /\b(UPI|NEFT|RTGS|IMPS|NACH|ACH)\b/i
  SEPARATORS = %r{[/\-*]+}

  POS = /\APOS\s+\S*X{2,}\S*\s+(?<merchant>.+)\z/i
  ATM = /\A(ATW|ATM|NWD|EAW|CASH WDL)\b/i
  INTEREST = /\A(INT\.?\s?PD|INTEREST|CREDIT INTEREST)\b/i

  CHANNEL_WORDS = /\A(UPI|NEFT|RTGS|IMPS|NACH|ACH)(\s+(CR|DR|C|D))?\z|\A(CR|DR|P2M|P2A|P2P|PAY|TRANSFER|(TO|BY)\s+TRANSFER)\z/i
  REMARK = /\A(PAYMENT|UPI PAYMENT|SENT USING|PAID VIA)\b/i
  IFSC = /\A[A-Z]{4}0[A-Z0-9]{6}\z/
  BANK_CODES = %w[AIRP BARB CNRB FDRL HDFC ICIC IDFB IDIB INDB IOBA KKBK PUNB PYTM SBIN UBIN UTIB YESB].freeze
  BANK_NAME = /\bBANK\b/i
  MANDATE_PREFIX = /\A(TP\s+)?(ACH|NACH)\s+/i

  def self.parse(narration)
    new(narration).parse
  end

  def initialize(narration)
    @narration = narration.to_s.strip
  end

  def parse
    name =
      if (match = POS.match(narration))
        match[:merchant]
      elsif narration.match?(ATM)
        "ATM cash withdrawal"
      elsif narration.match?(INTEREST)
        "Interest"
      elsif narration.match?(CHANNEL)
        counterparty
      end

    return Parsed.new(name: narration, notes: nil) if name.blank?

    Parsed.new(name: readable(name), notes: narration)
  end

  private
    attr_reader :narration

    # First token that names someone; a lone UPI handle stands in when nothing else does.
    def counterparty
      handle = nil

      narration.split(SEPARATORS).each do |raw|
        token = raw.strip
        next if token.empty? || token.match?(CHANNEL_WORDS)

        token = token.sub(MANDATE_PREFIX, "")

        if token.include?("@")
          handle ||= token
          next
        end

        return token unless noise?(token)
      end

      handle
    end

    def noise?(token)
      token.match?(CHANNEL_WORDS) ||
        token.match?(REMARK) ||
        token.match?(IFSC) ||
        token.upcase.in?(BANK_CODES) ||
        token.match?(BANK_NAME) ||
        token.include?("XX") ||
        reference?(token)
    end

    # Transaction, UTR and mandate references: one word carrying several digits.
    def reference?(token)
      !token.include?(" ") && token.count("0-9") >= 5
    end

    # Banks shout; a name written in capitals is shown in word case, anything else as is.
    def readable(name)
      name = name.strip
      return name if name.match?(/[a-z]/) || name.include?("@")

      name.split(/\s+/).map(&:capitalize).join(" ")
    end
end
