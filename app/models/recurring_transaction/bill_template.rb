class RecurringTransaction
  # Starting points for the bills most households in India pay: a name, a cadence, how
  # to estimate the amount and when to be reminded. Picking one only prefills the
  # add-bill form; everything stays editable. Nothing here is India-only, which is why
  # it is offered to every family.
  #
  # Variable bills (card statements, utilities) track the last amount actually paid
  # instead of the first one typed in. Prepaid mobile plans run in 28-day blocks, so
  # "every 4 weeks" matches them exactly where "monthly" would drift.
  class BillTemplate
    Template = Data.define(:key, :frequency_preset, :frequency_interval, :frequency_interval_unit,
                           :amount_strategy, :notify_days_before) do
      def name = I18n.t("recurring_transactions.bill_templates.#{key}")
    end

    TEMPLATES = [
      Template.new(key: "credit_card", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "last", notify_days_before: 5),
      Template.new(key: "electricity", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "last", notify_days_before: 3),
      Template.new(key: "broadband", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 3),
      Template.new(key: "mobile_postpaid", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 3),
      Template.new(key: "mobile_recharge", frequency_preset: "interval", frequency_interval: 4, frequency_interval_unit: "weekly",
                   amount_strategy: "fixed", notify_days_before: 2),
      Template.new(key: "dth_recharge", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 2),
      Template.new(key: "gas", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "last", notify_days_before: 3),
      Template.new(key: "water", frequency_preset: "quarterly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "last", notify_days_before: 5),
      Template.new(key: "rent", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 3),
      Template.new(key: "maintenance", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 3),
      Template.new(key: "loan_emi", frequency_preset: "monthly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 3),
      Template.new(key: "insurance", frequency_preset: "annual", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 15),
      Template.new(key: "school_fees", frequency_preset: "quarterly", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 7),
      Template.new(key: "property_tax", frequency_preset: "annual", frequency_interval: nil, frequency_interval_unit: nil,
                   amount_strategy: "fixed", notify_days_before: 15)
    ].freeze

    def self.all = TEMPLATES

    def self.find(key)
      TEMPLATES.find { |template| template.key == key.to_s }
    end
  end
end
