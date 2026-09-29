class AddFinancialYearStartMonthToFamilies < ActiveRecord::Migration[8.1]
  def change
    # Month the family's financial year begins (India: April). 1 means the calendar year.
    add_column :families, :financial_year_start_month, :integer, default: 1, null: false
    add_check_constraint :families, "financial_year_start_month BETWEEN 1 AND 12",
                         name: "chk_families_financial_year_start_month"
  end
end
