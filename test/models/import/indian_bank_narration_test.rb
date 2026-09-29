require "test_helper"

class Import::IndianBankNarrationTest < ActiveSupport::TestCase
  # Narration shapes as Indian banks print them in statement exports. Reference numbers,
  # handles and account masks are synthetic.
  CASES = {
    # UPI, dash-separated (HDFC)
    "UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-512345678901-PAYMENT FROM PHONE" => "Swiggy",
    "UPI-RAHUL KUMAR-rahul.k@okhdfcbank-HDFC0001234-412345678901-UPI" => "Rahul Kumar",
    # UPI, slash-separated (SBI)
    "TO TRANSFER-UPI/DR/512345678901/SWIGGY/YESB/swiggy@ybl/Pay--" => "Swiggy",
    "BY TRANSFER-UPI/CR/412345678901/RAHUL KUMAR/SBIN/rahulk@oksbi/UPI--" => "Rahul Kumar",
    # UPI (Axis)
    "UPI/P2M/412345678901/ZEPTO MARKETPLACE PRIVATE LIMITED/Payment from Ph/YES BANK LIMITED" => "Zepto Marketplace Private Limited",
    "UPI/P2A/412345678901/PRIYA SHARMA/Payment/HDFC BANK" => "Priya Sharma",
    # UPI (Kotak)
    "UPI/BIGBASKET/412345678901/Payment from Ph" => "Bigbasket",
    # UPI where the only party is the handle (ICICI)
    "UPI/412345678901/Payment fro/uber.rides@axisbank/Axis Bank Ltd" => "uber.rides@axisbank",
    # NEFT / RTGS / IMPS
    "NEFT CR-SBIN0001234-ACME CORP PVT LTD-SALARY SEP-N123456789012" => "Acme Corp Pvt Ltd",
    "BY TRANSFER-NEFT*HDFC0000001*N123456789*ACME CORP PVT LTD--" => "Acme Corp Pvt Ltd",
    "RTGS DR-ICIC0000104-SHARMA BUILDERS-HDFCR52026092912345678" => "Sharma Builders",
    "IMPS-512345678901-JOHN DOE-HDFC-XXXXXXX1234-TRANSFER" => "John Doe",
    # Card and cash
    "POS 416021XXXXXX1234 AMAZON PAY INDIA" => "Amazon Pay India",
    "ATW-416021XXXXXX1234-S1ACMU12-MUMBAI" => "ATM cash withdrawal",
    "NWD-416021XXXXXX1234-SPCNB123-BENGALURU" => "ATM cash withdrawal",
    # Mandates (SIP, EMI) and interest
    "ACH D- TP ACH ICICIPRU-1234567" => "Icicipru",
    "NACH-DR-BAJAJ FINANCE LTD-BFL1234567" => "Bajaj Finance Ltd",
    "INTEREST PAID TILL 30-SEP-2026" => "Interest",
    "CREDIT INTEREST CAPITALISED" => "Interest"
  }.freeze

  CASES.each do |narration, expected_name|
    test "names #{narration}" do
      assert_equal expected_name, Import::IndianBankNarration.parse(narration).name
    end
  end

  test "keeps the full narration as notes so rules and search can still use it" do
    parsed = Import::IndianBankNarration.parse("UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-512345678901-PAYMENT FROM PHONE")

    assert_equal "UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-512345678901-PAYMENT FROM PHONE", parsed.notes
  end

  test "passes unrecognised narrations through untouched without notes" do
    parsed = Import::IndianBankNarration.parse("  Cheque deposit 000123  ")

    assert_equal "Cheque deposit 000123", parsed.name
    assert_nil parsed.notes
  end

  test "leaves mixed-case names as the bank wrote them" do
    assert_equal "McDonald's India", Import::IndianBankNarration.parse("POS 416021XXXXXX1234 McDonald's India").name
  end

  test "handles blank input" do
    parsed = Import::IndianBankNarration.parse(nil)

    assert_equal "", parsed.name
    assert_nil parsed.notes
  end
end
