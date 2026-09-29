class AddSplitAmountColumnsToImports < ActiveRecord::Migration[8.1]
  def change
    # Statements that put money out and money in in separate columns (Withdrawal / Deposit,
    # Debit / Credit), used by the "split_columns" amount type strategy.
    add_column :imports, :outflow_col_label, :string
    add_column :imports, :inflow_col_label, :string
    # Rewrite Indian bank narrations (UPI, NEFT, IMPS, …) into counterparty names on import.
    add_column :imports, :clean_bank_narrations, :boolean, default: false, null: false
  end
end
