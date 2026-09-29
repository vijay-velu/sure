class ActualImport < Import
  after_create :set_mappings

  DEFAULT_COLUMN_MAPPINGS = {
    signage_convention: "inflows_positive",
    date_col_label: "Date",
    date_format: "%Y-%m-%d",
    name_col_label: "Payee",
    amount_col_label: "Amount",
    account_col_label: "Account",
    category_col_label: "Category",
    notes_col_label: "Notes"
  }.freeze

  CATEGORY_GROUP_COLUMN = "Category_Group".freeze
  SPLIT_AMOUNT_COLUMN = "Split_Amount".freeze

  # Actual books an account's opening balance as a transaction from this payee, filed under the
  # "Starting Balances" income category on budget accounts and uncategorized on tracking accounts.
  # Both names are created by Actual itself, so they are stable across budgets.
  STARTING_BALANCE_PAYEE = "Starting Balance".freeze
  STARTING_BALANCES_CATEGORY = "Starting Balances".freeze

  def self.default_column_mappings
    DEFAULT_COLUMN_MAPPINGS
  end

  def generate_rows_from_csv
    rows.destroy_all

    mapped_rows = csv_rows.each.with_index(1).filter_map do |row, index|
      # A split parent carries its total in Split_Amount and 0 in Amount; its children are
      # exported as rows of their own, so importing the parent would only add a $0 entry.
      next if split_parent?(row)

      {
        source_row_number: index,
        account: row[account_col_label].to_s,
        date: row[date_col_label].to_s,
        amount: signed_csv_amount(row).to_s,
        currency: default_currency.to_s,
        name: row_name(row),
        # Opening balances become the account's opening anchor (see #import!), so their
        # "Income: Starting Balances" category is never mapped or created.
        category: starting_balance_csv_row?(row) ? "" : combined_category(row),
        notes: row[notes_col_label].to_s
      }
    end

    rows.insert_all!(mapped_rows) if mapped_rows.any?
    update_column(:rows_count, rows.count)
  end

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      opening_balances = Hash.new(0)

      rows.each do |row|
        account = mappings.accounts.mappable_for(row.account)

        if starting_balance_row?(row)
          opening_balances[account] += row.signed_amount
          next
        end

        category = mappings.categories.mappable_for(row.category)

        entry = account.entries.build \
          date: row.date_iso,
          amount: row.signed_amount,
          name: row.name,
          currency: account.currency.presence || family.currency,
          notes: row.notes,
          entryable: Transaction.new(category: category),
          import: self,
          # Like the other file imports: once a bank connection (e.g. SimpleFIN) is linked,
          # the overlapping days it re-sends are matched onto these entries rather than
          # overwriting the payees and categories carried over from Actual.
          import_locked: true

        entry.save!
      end

      opening_balances.each { |account, amount| apply_opening_balance!(account, amount) }
    end
  end

  def mapping_steps
    [ Import::CategoryMapping, Import::AccountMapping ]
  end

  def required_column_keys
    %i[date amount]
  end

  def column_keys
    %i[date amount name category account notes]
  end

  def csv_template
    template = <<~CSV
      Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared
      Checking Account,2024-01-01,Employer,Monthly salary,Income,Paycheck,2500.00,0,Reconciled
      Credit Card,2024-01-03,Coffee Shop,Morning coffee,Food,Coffee,-4.25,0,Cleared
    CSV

    CSV.parse(template, headers: true)
  end

  def signed_csv_amount(csv_row)
    csv_row[amount_col_label].to_d
  end

  private
    def split_parent?(csv_row)
      csv_row[amount_col_label].to_d.zero? && csv_row[SPLIT_AMOUNT_COLUMN].to_d.nonzero?
    end

    def starting_balance_csv_row?(csv_row)
      csv_row[name_col_label].to_s.strip == STARTING_BALANCE_PAYEE &&
        csv_row[category_col_label].to_s.strip.in?([ "", STARTING_BALANCES_CATEGORY ])
    end

    # Rows keep the payee as their name and had their category cleared in
    # #generate_rows_from_csv, which is what identifies them here.
    def starting_balance_row?(row)
      row.name == STARTING_BALANCE_PAYEE && row.category.blank?
    end

    # Records Actual's starting balance as the account's opening anchor instead of a
    # transaction: it is what the account held before its history begins, not income or an
    # expense. Entries use Sure's sign (positive = outflow), so an asset's opening value is
    # the negated sum while a liability's owed amount is the sum as is.
    #
    # The anchor is set, not added to: an account created in Sure before the import may
    # already carry one, and Actual's starting balance is what its history starts from. It is
    # dated the day before the account's oldest entry so the imported history follows it.
    def apply_opening_balance!(account, signed_amount)
      balance = account.classification == "liability" ? signed_amount : -signed_amount
      anchor_entry = account.valuations.opening_anchor.first&.entry
      oldest_entry_date = account.entries.where.not(id: anchor_entry&.id).minimum(:date)

      result = account.set_opening_anchor_balance(balance: balance, date: oldest_entry_date&.prev_day)
      unless result.success?
        raise StandardError, "Could not set the opening balance of #{account.name}: #{result.error}"
      end

      # A newly created anchor belongs to this import, so reverting the import removes it.
      account.valuations.opening_anchor.first&.entry&.update!(import: self) if anchor_entry.nil?
    end

    def set_mappings
      assign_attributes(self.class.default_column_mappings)
      save!
    end

    # Actual Budget exports reconciliation and starting-balance rows with a blank
    # Payee. Entry requires a name, so fall back to the Notes column (which usually
    # carries text like "Reconciliation balance adjustment") and finally to the
    # generic default, matching the blank-name handling in Import and MintImport.
    def row_name(row)
      row[name_col_label].to_s.presence ||
        row[notes_col_label].to_s.presence ||
        default_row_name
    end

    def combined_category(row)
      category = row[category_col_label].to_s.strip
      category_group = row[CATEGORY_GROUP_COLUMN].to_s.strip

      return category if category_group.blank?
      return category_group if category.blank?

      "#{category_group}: #{category}"
    end
end
