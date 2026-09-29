require "test_helper"

class MintImportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "default column mappings are applied after create" do
    import = @family.imports.create!(type: "MintImport")

    MintImport.default_column_mappings.each do |attribute, value|
      assert_equal value, import.public_send(attribute)
    end
  end

  test "generated rows preserve stable source row numbers" do
    import = @family.imports.create!(
      type: "MintImport",
      raw_file_str: file_fixture("imports/mint.csv").read,
      col_sep: ","
    )

    import.generate_rows_from_csv

    assert_equal (1..10).to_a, import.rows.order(:source_row_number).pluck(:source_row_number)
  end

  test "published entries are import locked so a provider sync links instead of renaming them" do
    account = accounts(:depository)
    import = @family.imports.create!(type: "MintImport", col_sep: ",", raw_file_str: <<~CSV)
      Date,Description,Amount,Transaction Type,Category,Account Name,Labels,Notes
      01/01/2024,Trader Joes,42.50,debit,,Checking,,
    CSV
    import.generate_rows_from_csv
    import.mappings.create! key: "Checking", mappable: account, type: "Import::AccountMapping"
    import.reload
    import.publish
    import.reload

    assert_equal "complete", import.status
    entry = import.entries.sole
    assert entry.import_locked?

    # A bank connection re-sending the same day and amount must link the entry, not rename it.
    linked = Account::ProviderImportAdapter.new(account).import_transaction(
      external_id: "simplefin_trader_joes",
      amount: entry.amount,
      currency: entry.currency,
      date: entry.date,
      name: "TRADER JOE'S #552 PORTLAND OR",
      source: "simplefin"
    )

    assert_equal entry.id, linked.id
    entry.reload
    assert_equal "Trader Joes", entry.name
    assert_equal "simplefin_trader_joes", entry.external_id
  end
end
