require "test_helper"

class Import::BankPresetTest < ActiveSupport::TestCase
  test "recognises an HDFC statement export" do
    preset = Import::BankPreset.detect(<<~CSV)
      Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
      01/09/26,UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-512345678901-PAYMENT,0000512345678901,01/09/26,450.00,,98550.00
    CSV

    assert_equal "HDFC Bank", preset.bank
    assert_equal 0, preset.header_row_index
    assert_equal "Date", preset.date_col_label
    assert_equal "Narration", preset.name_col_label
    assert_equal "Withdrawal Amt.", preset.outflow_col_label
    assert_equal "Deposit Amt.", preset.inflow_col_label
  end

  test "recognises an ICICI export, whose headers pad the currency" do
    preset = Import::BankPreset.detect(<<~CSV)
      S No.,Value Date,Transaction Date,Cheque Number,Transaction Remarks,Withdrawal Amount (INR ),Deposit Amount (INR ),Balance (INR )
      1,01/09/2026,01/09/2026,-,UPI/412345678901/Payment fro/uber.rides@axisbank/Axis Bank Ltd,245.00,0.00,10000.00
    CSV

    assert_equal "ICICI Bank", preset.bank
    assert_equal "Transaction Date", preset.date_col_label
    assert_equal "Transaction Remarks", preset.name_col_label
    assert_equal "Withdrawal Amount (INR )", preset.outflow_col_label
  end

  test "recognises SBI and Axis exports" do
    sbi = Import::BankPreset.detect("Txn Date,Value Date,Description,Ref No./Cheque No.,Debit,Credit,Balance\n")
    axis = Import::BankPreset.detect("Tran Date,CHQNO,PARTICULARS,DR,CR,BAL,SOL\n")

    assert_equal [ "State Bank of India", "Txn Date", "Description", "Debit", "Credit" ],
      [ sbi.bank, sbi.date_col_label, sbi.name_col_label, sbi.outflow_col_label, sbi.inflow_col_label ]
    assert_equal [ "Axis Bank", "Tran Date", "PARTICULARS", "DR", "CR" ],
      [ axis.bank, axis.date_col_label, axis.name_col_label, axis.outflow_col_label, axis.inflow_col_label ]
  end

  test "finds the header row below the account summary banks print first" do
    preset = Import::BankPreset.detect(<<~CSV)
      Account Name,MR VIJAY
      Account Number,XXXXXXXX1234
      ,
      Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
    CSV

    assert_equal 3, preset.header_row_index
  end

  test "any statement with withdrawal and deposit columns gets the generic preset" do
    preset = Import::BankPreset.detect("Posting Date,Details,Withdrawals,Deposits,Balance\n")

    assert_nil preset.bank
    assert_equal [ "Posting Date", "Details", "Withdrawals", "Deposits" ],
      [ preset.date_col_label, preset.name_col_label, preset.outflow_col_label, preset.inflow_col_label ]
  end

  test "a single signed amount column is left to manual configuration" do
    assert_nil Import::BankPreset.detect("Date,Payee,Amount\n2026-09-01,Swiggy,-450\n")
  end

  test "a combined Dr/Cr indicator column is not mistaken for amounts" do
    assert_nil Import::BankPreset.detect("Date,Description,Amount,Dr / Cr\n")
  end
end
