require "csv"

# Recognises bank statement CSVs that keep money out and money in in separate columns
# (Withdrawal / Deposit, Debit / Credit, Dr / Cr) — the usual shape of Indian bank
# exports — and works out which columns hold the date, the narration and the two amounts.
#
# Matching is on normalised header names (lowercase letters and digits only), so
# "Withdrawal Amount (INR )" and "Withdrawal Amt." both count. Banks print account details
# above the table, so the header is searched for in the first rows of the file. A few
# banks are named when their header set is recognised; any other statement with the same
# shape still gets the generic preset. Nothing matched means manual configuration.
class Import::BankPreset
  Preset = Data.define(:bank, :header_row_index, :date_col_label, :name_col_label, :outflow_col_label, :inflow_col_label)

  HEADER_SEARCH_ROWS = 40

  # First match wins within each list.
  DATE_HEADERS = %w[transactiondate txndate trandate postingdate date valuedate valuedt].freeze
  NAME_HEADERS = %w[narration transactionremarks description particulars details transactiondetails remarks].freeze
  OUTFLOW_HEADER = /\A(withdrawal|debit)|\Adr\z/
  INFLOW_HEADER = /\A(deposit|credit)|\Acr\z/

  BANKS = {
    "HDFC Bank" => %w[narration withdrawalamt depositamt],
    "ICICI Bank" => %w[transactionremarks withdrawalamountinr depositamountinr],
    "State Bank of India" => %w[txndate description debit credit],
    "Axis Bank" => %w[trandate particulars dr cr]
  }.freeze

  def self.detect(csv_str, col_sep: ",")
    csv_str.to_s.lines.first(HEADER_SEARCH_ROWS).each_with_index do |line, index|
      headers = parse_line(line, col_sep)
      next if headers.blank?

      preset = from_headers(headers, index)
      return preset if preset
    end

    nil
  end

  def self.from_headers(headers, header_row_index)
    by_key = headers.compact.map(&:strip).reject(&:empty?).index_by { |header| normalize(header) }

    date = pick(by_key, DATE_HEADERS)
    name = pick(by_key, NAME_HEADERS)
    outflow = by_key.find { |key, _| key.match?(OUTFLOW_HEADER) }&.last
    inflow = by_key.find { |key, _| key.match?(INFLOW_HEADER) }&.last
    return nil unless date && name && outflow && inflow

    bank = BANKS.find { |_, keys| keys.all? { |key| by_key.key?(key) } }&.first

    Preset.new(bank:, header_row_index:, date_col_label: date, name_col_label: name,
               outflow_col_label: outflow, inflow_col_label: inflow)
  end

  def self.normalize(header)
    header.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def self.pick(by_key, candidates)
    candidates.each { |key| return by_key[key] if by_key.key?(key) }
    nil
  end

  def self.parse_line(line, col_sep)
    CSV.parse_line(line, col_sep: col_sep)
  rescue CSV::MalformedCSVError
    nil
  end

  private_class_method :from_headers, :normalize, :pick, :parse_line
end
