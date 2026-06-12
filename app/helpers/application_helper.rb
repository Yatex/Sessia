module ApplicationHelper
  NAV_ITEMS = [
    [:agenda, :dashboard_path],
    [:sessions, :sessions_path],
    [:clients, :clients_path],
    [:payments, :payments_path],
    [:analytics, :analytics_path]
  ].freeze

  ADMIN_NAV_ITEMS = [
    ["Platform analytics", :admin_analytics_path],
    ["Users", :admin_users_path],
    ["AI messages", :admin_ai_messages_path]
  ].freeze

  def nav_items
    NAV_ITEMS.map { |key, helper| [t("navigation.#{key}"), public_send(helper)] }
  end

  def admin_nav_items
    ADMIN_NAV_ITEMS.map { |label, helper| [label, public_send(helper)] }
  end

  def google_calendar_feature_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["GOOGLE_CALENDAR_UI_ENABLED"])
  end

  def nav_link_class(path)
    request.path == path ? "nav-link active" : "nav-link"
  end

  def status_badge(value)
    normalized = value.to_s.dasherize
    content_tag(:span, status_label(value), class: "status-badge #{normalized}")
  end

  def payment_status_badge(value)
    normalized = value.to_s.dasherize
    label = value.to_s == "pending" ? status_label("unpaid") : status_label(value)
    content_tag(:span, label, class: "status-badge payment-status #{normalized}")
  end

  def compact_date(date)
    date.strftime("%b %-d")
  end

  def session_time_range(session_record)
    "#{l(session_record.start_time, format: :short_time)} - #{l(session_record.end_time, format: :short_time)}"
  end

  def compact_session_time_range(session_record)
    "#{session_record.start_time.strftime("%H:%M")} - #{session_record.end_time.strftime("%H:%M")}"
  end

  def calendar_slot_time(day, slot_minutes)
    Time.zone.local(day.year, day.month, day.day, slot_minutes / 60, slot_minutes % 60)
  end

  def slot_time_label(slot_minutes)
    format("%02d:%02d", slot_minutes / 60, slot_minutes % 60)
  end

  def money_from_cents(cents, currency = "USD")
    number_to_currency(cents.to_i / 100.0, unit: "#{currency.presence || "USD"} ")
  end

  def session_price(session_record)
    money_from_cents(session_record.price_cents, session_record.currency)
  end

  def confirmation_signal_tone(session_record)
    return "neutral" if session_record.cancelled? || session_record.no_show?
    return "good" if session_record.confirmation_confirmed?
    return "danger" if session_record.confirmation_declined?
    return "warning" if session_record.confirmation_pending? || session_record.confirmation_maybe?

    "neutral"
  end

  def slot_session_tone(session_record)
    return "cancelled" if session_record.cancelled? || session_record.no_show? || session_record.confirmation_declined?
    return "confirmed" if session_record.confirmation_confirmed?

    "pending"
  end

  def session_payment_icon(session_record)
    paid = session_record.payment_paid?
    label = paid ? t("statuses.paid") : t("statuses.unpaid")

    content_tag(:span, paid ? "$" : "!", class: "session-payment-icon #{paid ? "paid" : "unpaid"}", title: label, aria: { label: label })
  end

  def confirmation_signal_label(session_record)
    return status_label("cancelled") if session_record.cancelled?
    return status_label("no_show") if session_record.no_show?

    status_label(session_record.confirmation_status)
  end

  def payment_signal_tone(session_record)
    return "neutral" if session_record.payment_cancelled? || session_record.payment_not_tracked? || session_record.payment_waived? || session_record.payment_refunded?
    return "good" if session_record.payment_paid?
    return "warning" if session_record.payment_partially_paid?
    return "danger" if session_record.payment_pending? || session_record.payment_overdue?

    "neutral"
  end

  def payment_signal_label(session_record)
    return status_label("unpaid") if session_record.payment_pending?

    status_label(session_record.payment_status)
  end

  def unpaid_payment_count(session_records)
    session_records.count { |session_record| session_record.payment_pending? || session_record.payment_overdue? }
  end

  def client_whatsapp_ai_start_url(client)
    number = sessia_whatsapp_number
    return if number.blank?

    "https://wa.me/#{number}?text=#{CGI.escape(client_whatsapp_ai_start_message(client))}"
  end

  def client_whatsapp_ai_start_message(client)
    if current_user&.locale.to_s.start_with?("es")
      "Hola Sessia, soy #{client.name}. Quiero conectar mis sesiones por WhatsApp."
    else
      "Hi Sessia, this is #{client.name}. I want to connect my sessions on WhatsApp."
    end
  end

  def sessia_whatsapp_number
    Messaging::WhatsappAddress.normalize(ENV["TWILIO_WHATSAPP_FROM"])
  end

  def confirmed_session_count(session_records)
    session_records.count(&:confirmation_confirmed?)
  end

  def plan_configured?(plan)
    ENV[plan.price_env_key].present? || ENV["STRIPE_PRICE_ID"].present?
  end

  def plan_fit_class(plan, client_count)
    return "over-limit" unless plan.covers_client_count?(client_count)
    return "recommended" if StripeBilling.recommended_plan_for(client_count)&.tier == plan.tier

    "available"
  end

  def iana_time_zone_options
    options = ActiveSupport::TimeZone.all.map do |zone|
      identifier = zone.tzinfo.identifier
      label = "#{identifier} (#{zone.formatted_offset})"
      [label, identifier]
    end.uniq { |_label, identifier| identifier }.sort_by(&:first)

    [["UTC (+00:00)", "UTC"]] + options.reject { |_label, identifier| identifier == "UTC" }
  end

  def language_options
    User::AVAILABLE_LOCALES.map { |value, label| [label, value] }
  end

  def public_language_switcher
    target_locale = I18n.locale.to_s == "es" ? "en" : "es"
    label = target_locale == "es" ? "ES" : "EN"

    button_to label, locale_path,
      method: :patch,
      params: { locale: target_locale },
      class: "language-switcher",
      form_class: "language-switcher-form"
  end

  def topbar_title
    t("topbar.#{controller_name}", default: controller_name.tr("_", " ").humanize)
  end

  def ai_message_debug_payload(message)
    return {} if message.blank?

    provider = message.metadata.to_h["provider"].is_a?(Hash) ? message.metadata["provider"] : {}
    template = message.metadata.to_h["whatsapp_template"].is_a?(Hash) ? message.metadata["whatsapp_template"] : provider["template"]
    request = provider["request"].is_a?(Hash) ? provider["request"] : {}

    {
      template_name: template&.dig("name"),
      content_sid: template&.dig("content_sid") || request["content_sid"],
      content_variables: template&.dig("variables") || parse_json_object(request["content_variables"]),
      provider_status: provider["status"],
      provider_http_status: provider["http_status"],
      provider_error_code: provider["error_code"],
      provider_more_info: provider["more_info"],
      provider_error_message: provider["error_message"],
      stored_error: message.error_message
    }.compact
  end

  def ai_message_likely_cause(message)
    payload = ai_message_debug_payload(message)
    error_text = [payload[:provider_error_message], payload[:stored_error]].compact.join(" ").downcase
    return if error_text.blank?

    if error_text.include?("content variables")
      "Likely template mismatch: the Twilio ContentSid does not accept the variables Sessia sent. Check that the approved template uses the same variable numbers shown below."
    elsif error_text.include?("content sid")
      "Likely template configuration issue: check that this ContentSid exists in the same Twilio account and is approved for WhatsApp."
    elsif error_text.include?("outside") && error_text.include?("window")
      "Likely WhatsApp conversation-window issue: proactive messages need an approved template outside the 24-hour response window."
    end
  end

  def pretty_json(value)
    JSON.pretty_generate(value)
  rescue JSON::GeneratorError
    value.to_s
  end

  def parse_json_object(value)
    return value if value.is_a?(Hash)
    return if value.blank?

    parsed = JSON.parse(value.to_s)
    parsed if parsed.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def status_label(value)
    t("statuses.#{value}", default: value.to_s.humanize)
  end
end
