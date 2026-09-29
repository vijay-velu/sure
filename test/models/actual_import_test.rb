require "test_helper"

class ActualImportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "default column mappings are applied after create" do
    import = @family.imports.create!(type: "ActualImport")

    ActualImport.default_column_mappings.each do |attribute, value|
      assert_equal value, import.public_send(attribute)
    end
  end

  test "generated rows preserve stable source row numbers" do
    import = @family.imports.create!(
      type: "ActualImport",
      raw_file_str: file_fixture("imports/actual.csv").read,
      col_sep: ","
    )

    import.generate_rows_from_csv

    assert_equal (1..5).to_a, import.rows.order(:source_row_number).pluck(:source_row_number)
  end

  test "generated rows combine category group and category" do
    import = @family.imports.create!(
      type: "ActualImport",
      raw_file_str: file_fixture("imports/actual.csv").read,
      col_sep: ","
    )

    import.generate_rows_from_csv

    assert_equal "Food: Coffee", import.rows.order(:source_row_number).second.category
    assert_equal "Income: Paycheck", import.rows.order(:source_row_number).third.category
    assert_equal "Transfer", import.rows.order(:source_row_number).fourth.category
  end

  test "generated rows fall back to category group when category is blank" do
    import = @family.imports.create!(
      type: "ActualImport",
      raw_file_str: file_fixture("imports/actual.csv").read.sub("Housing,Rent", "Housing,"),
      col_sep: ","
    )

    import.generate_rows_from_csv

    assert_equal "Housing", import.rows.order(:source_row_number).first.category
  end

  test "blank payee falls back to notes, then to the default row name" do
    import = @family.imports.create!(
      type: "ActualImport",
      raw_file_str: file_fixture("imports/actual.csv").read,
      col_sep: ","
    )

    import.generate_rows_from_csv

    # Reconciliation row has a blank Payee but a meaningful Notes value
    assert_equal "Reconciliation balance adjustment",
      import.rows.order(:source_row_number).last.name

    # When both Payee and Notes are blank, fall back to the generic default name
    blank_both_csv = <<~CSV
      Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared
      Checking Account,2024-01-04,,,Income,Income,0.43,0,Reconciled
    CSV

    blank_both = @family.imports.create!(type: "ActualImport", raw_file_str: blank_both_csv, col_sep: ",")
    blank_both.generate_rows_from_csv

    assert_equal "Imported item", blank_both.rows.order(:source_row_number).first.name
  end

  test "imports rows with a blank payee without failing the whole import" do
    csv = <<~CSV
      Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared
      Cash,2024-01-01,Employer,Salary,Income,Paycheck,2500.00,0,Reconciled
      Cash,2024-01-04,,Reconciliation balance adjustment,Income,Income,0.43,0,Reconciled
    CSV

    import = @family.imports.create!(type: "ActualImport", raw_file_str: csv, col_sep: ",")
    import.generate_rows_from_csv

    import.mappings.create! key: "Income: Paycheck", create_when_empty: true, type: "Import::CategoryMapping"
    import.mappings.create! key: "Income: Income", create_when_empty: true, type: "Import::CategoryMapping"
    import.mappings.create! key: "Cash", mappable: accounts(:depository), type: "Import::AccountMapping"
    import.reload

    assert_difference -> { Entry.count } => 2, -> { Transaction.count } => 2 do
      import.publish
    end

    assert_equal "complete", import.status
    assert_includes import.entries.reload.map(&:name), "Reconciliation balance adjustment"
  end

  test "split parent rows are skipped because their children carry the amounts" do
    csv = <<~CSV
      Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared
      Visa,2024-01-12,Costco,(SPLIT INTO 2) ,,,0,-100,Cleared
      Visa,2024-01-12,Costco,(SPLIT 1 OF 2) ,Food,Groceries,-60,0,Cleared
      Visa,2024-01-12,Costco,(SPLIT 2 OF 2) ,Home,Household,-40,0,Cleared
    CSV

    import = @family.imports.create!(type: "ActualImport", raw_file_str: csv, col_sep: ",")
    import.generate_rows_from_csv

    rows = import.rows.order(:source_row_number)
    assert_equal [ 2, 3 ], rows.pluck(:source_row_number)
    assert_equal %w[-60 -40], rows.pluck(:amount).map { |amount| amount.to_d.to_i.to_s }
  end

  test "starting balance rows are left out of category mapping" do
    import = @family.imports.create!(type: "ActualImport", raw_file_str: starting_balance_csv, col_sep: ",")
    import.generate_rows_from_csv
    import.sync_mappings

    keys = import.mappings.where(type: "Import::CategoryMapping").pluck(:key)
    assert_includes keys, "Food: Groceries"
    assert_empty keys.grep(/Starting Balances/)
  end

  test "starting balances become opening anchors instead of transactions" do
    checking = accounts(:depository)
    card = accounts(:credit_card)

    import = publish_starting_balance_import(checking:, card:)

    assert_equal "complete", import.status
    assert_equal 1, import.entries.where(entryable_type: "Transaction").count
    assert import.entries.where(entryable_type: "Transaction").all?(&:import_locked?)
    assert_not import.entries.exists?(name: ActualImport::STARTING_BALANCE_PAYEE)

    # An asset opens at the balance Actual recorded; a liability at what is owed.
    card = Account.find(card.id)
    assert_equal 5000, Account.find(checking.id).opening_anchor_balance
    assert_equal 500, card.opening_anchor_balance
    assert_equal Date.new(2023, 12, 31), card.opening_anchor_date
    assert_not @family.categories.exists?(name: ActualImport::STARTING_BALANCES_CATEGORY)
  end

  test "a starting balance replaces an existing opening anchor and precedes the history" do
    checking = accounts(:depository)
    checking.set_opening_anchor_balance(balance: 123, date: 1.day.ago.to_date)

    publish_starting_balance_import(checking:, card: accounts(:credit_card))

    checking = Account.find(checking.id)
    assert_equal 5000, checking.opening_anchor_balance
    assert_operator checking.opening_anchor_date, :<, checking.entries.where(entryable_type: "Transaction").minimum(:date)
  end

  test "reverting the import removes the opening anchors it created" do
    checking = accounts(:depository)
    checking.valuations.opening_anchor.each { |valuation| valuation.entry.destroy! }

    import = publish_starting_balance_import(checking:, card: accounts(:credit_card))
    # Fresh instances: Account memoizes its opening-balance lookup across #reload.
    assert Account.find(checking.id).has_opening_anchor?

    import.revert

    assert_not Account.find(checking.id).has_opening_anchor?
  end

  private
    # Actual files a budget account's starting balance under "Income: Starting Balances"
    # and a tracking account's with no category; both use Actual's own payee.
    def starting_balance_csv
      <<~CSV
        Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared
        Checking,2024-06-01,Starting Balance,,Income,Starting Balances,5000,0,Cleared
        Card,2024-06-01,Starting Balance,,,,-500,0,Cleared
        Card,2024-01-01,Trader Joes,,Food,Groceries,-42.50,0,Cleared
      CSV
    end

    def publish_starting_balance_import(checking:, card:)
      import = @family.imports.create!(type: "ActualImport", raw_file_str: starting_balance_csv, col_sep: ",")
      import.generate_rows_from_csv
      import.mappings.create! key: "Food: Groceries", create_when_empty: true, type: "Import::CategoryMapping"
      import.mappings.create! key: "Checking", mappable: checking, type: "Import::AccountMapping"
      import.mappings.create! key: "Card", mappable: card, type: "Import::AccountMapping"
      import.reload
      import.publish
      import.reload
    end
end
