# The text of one reminder digest, shared by email and push so both say the same thing.
class BillReminder::Message
  attr_reader :family, :items

  def initialize(family, items)
    @family = family
    @items = items.sort_by { |item| [ item.overdue? ? 0 : 1, item.due_on ] }
  end

  def title
    I18n.with_locale(family.locale) do
      if items.any?(&:overdue?)
        I18n.t("bill_reminders.message.title_overdue", count: items.count(&:overdue?))
      else
        I18n.t("bill_reminders.message.title_due", count: items.size)
      end
    end
  end

  def lines
    I18n.with_locale(family.locale) { items.map { |item| line(item) } }
  end

  def body
    lines.join("\n")
  end

  def urgent?
    items.any?(&:overdue?)
  end

  def url
    Rails.application.routes.url_helpers.bills_url(**url_options)
  end

  # Structured form for JSON webhooks.
  def as_json(*)
    {
      title: title,
      message: body,
      url: url,
      bills: items.map do |item|
        { name: item.series.display_name, amount: amount(item).amount.to_s, currency: amount(item).currency.iso_code,
          due_on: item.due_on.iso8601, state: item.kind, autopay: item.series.autopay? }
      end
    }
  end

  def amount(item)
    item.occurrence.remaining_amount_money
  end

  private
    def line(item)
      key = item.overdue? ? "overdue_line" : "due_line"
      text = I18n.t("bill_reminders.message.#{key}",
                    name: item.series.display_name,
                    amount: amount(item).format,
                    date: I18n.l(item.due_on, format: :short),
                    when: relative_day(item.due_on))
      item.series.autopay? ? "#{text} #{I18n.t('bill_reminders.message.autopay')}" : text
    end

    def relative_day(date)
      days = (date - Time.use_zone(family.timezone.presence || Time.zone) { Date.current }).to_i

      case days
      when 0 then I18n.t("bill_reminders.message.today")
      when 1 then I18n.t("bill_reminders.message.tomorrow")
      when 2.. then I18n.t("bill_reminders.message.in_days", count: days)
      else I18n.t("bill_reminders.message.days_ago", count: -days)
      end
    end

    def url_options
      config = Rails.application.config
      options = (config.action_mailer.default_url_options || {}).dup
      options[:protocol] ||= "https" if config.force_ssl || config.assume_ssl
      options
    end
end
