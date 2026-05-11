module Messaging
  class WhatsappTemplateCatalog
    Template = Struct.new(:name, :content_sid, :variables, keyword_init: true)

    DEFAULT_CONTENT_SIDS = {
      "session_confirmation_en" => "HX88edb7ea06c9c6b8f992ee87489e64ca",
      "session_confirmation_es" => "HXC411f914c8175172ed07300bc46af7557",
      "session_follow_up_en" => "HXeb67c819abe3002bab03a39f8d57966a",
      "session_follow_up_es" => "HXbe082d8c324c5f7c9cf5d41db1a9379f",
      "payment_reminder_en" => "HX34a075355540af7955a171de8bbc7039",
      "payment_reminder_es" => "HX604c387dda71de0e767e17e1fc316706",
      "session_feedback_en" => "HXe5e4f69e7c3acbe7280e60f0474bfbe6",
      "session_feedback_es" => "HXbc3479ac404843ec319c97c70aff8dab",
      "session_change_en" => "HX1530930bdc064b620e60c91b508788d3",
      "session_change_es" => "HX8a9046747b136959cb4aa2bf8f5cab49",
      "session_canceled_en" => "HXe3f046c7efe59a438f187ed5786e5379",
      "session_canceled_es" => "HXac1b2296108b894b44b6bef12da84e67",
      "session_reminder_en" => "HX1caa931ff7da7bb2017afa47bd659931",
      "session_reminder_es" => "HX514f9b18619bfe2023ec8d177893629b"
    }.freeze

    LEGACY_ENV_ALIASES = {
      "session_confirmation" => "attendance_confirmation",
      "session_follow_up" => "attendance_follow_up"
    }.freeze

    AUTOMATION_TEMPLATE_NAMES = {
      "confirm_session" => "session_confirmation",
      "follow_up_no_response" => "session_follow_up",
      "payment_reminder" => "payment_reminder",
      "send_pre_session_reminder" => "session_reminder",
      "ask_feedback_after_session" => "session_feedback",
      "blocked_time_rebooking" => "session_change"
    }.freeze

    def initialize(user:, client:, session: nil, ai_task: nil)
      @user = user
      @client = client
      @session = session
      @ai_task = ai_task
    end

    def template
      name = template_name
      return if name.blank?

      content_sid = content_sid_for(name)
      return if content_sid.blank?

      Template.new(
        name: name,
        content_sid: content_sid,
        variables: variables_for(name)
      )
    end

    private

    attr_reader :user, :client, :session, :ai_task

    def template_name
      base_name = AUTOMATION_TEMPLATE_NAMES[ai_task&.automation_key.to_s]
      return if base_name.blank?

      base_name = "session_canceled" if base_name == "session_change" && session&.cancelled?
      "#{base_name}_#{language}"
    end

    def language
      user&.locale.to_s.presence_in(%w[en es]) || User::DEFAULT_LOCALE
    end

    def content_sid_for(name)
      env_keys_for(name).each do |env_key|
        value = ENV[env_key].to_s.strip
        return value if value.present?
      end

      DEFAULT_CONTENT_SIDS[name]
    end

    def env_keys_for(name)
      base_name, locale = name.to_s.rpartition("_").then { |parts| [parts.first, parts.last] }
      keys = ["TWILIO_CONTENT_SID_#{base_name.upcase}_#{locale.upcase}"]
      legacy_base_name = LEGACY_ENV_ALIASES[base_name]
      keys << "TWILIO_CONTENT_SID_#{legacy_base_name.upcase}_#{locale.upcase}" if legacy_base_name.present?
      keys
    end

    def variables_for(name)
      case name
      when /\Asession_confirmation_/, /\Asession_follow_up_/, /\Asession_reminder_/, /\Asession_feedback_/, /\Asession_canceled_/
        session_variables
      when /\Apayment_reminder_/
        payment_variables
      when /\Asession_change_/
        schedule_change_variables
      else
        {}
      end
    end

    def session_variables
      {
        "1" => client_name,
        "2" => session_title,
        "3" => session_date,
        "4" => session_time
      }
    end

    def payment_variables
      {
        "1" => client_name,
        "2" => payment_amount,
        "3" => session_title
      }
    end

    def schedule_change_variables
      {
        "1" => client_name,
        "2" => session_title,
        "3" => schedule_change_detail
      }
    end

    def client_name
      client&.name.to_s.presence || (language == "es" ? "cliente" : "client")
    end

    def session_title
      session&.title.to_s.presence || (language == "es" ? "la sesion" : "the session")
    end

    def session_start
      (session&.start_time || Time.current).in_time_zone(user_time_zone)
    end

    def original_session_start
      Time.zone.parse(ai_task&.context_data.to_h["original_start_time"].to_s)&.in_time_zone(user_time_zone)
    rescue ArgumentError, TypeError
      nil
    end

    def user_time_zone
      user&.time_zone.presence || Time.zone.name
    end

    def session_date
      I18n.with_locale(language) { I18n.l(session_start.to_date, format: :long) }
    end

    def session_time
      I18n.with_locale(language) { I18n.l(session_start, format: :short_time) }
    end

    def original_session_date
      return session_date if original_session_start.blank?

      I18n.with_locale(language) { I18n.l(original_session_start.to_date, format: :long) }
    end

    def original_session_time
      return session_time if original_session_start.blank?

      I18n.with_locale(language) { I18n.l(original_session_start, format: :short_time) }
    end

    def payment_amount
      return language == "es" ? "el monto pendiente" : "the pending amount" if session.blank? || session.price_cents.to_i.zero?

      format("%s %.2f", session.currency.presence || "USD", session.price_cents.to_i / 100.0)
    end

    def schedule_change_detail
      if language == "es"
        "la sesion paso del #{original_session_date} a las #{original_session_time} al #{session_date} a las #{session_time}"
      else
        "the session moved from #{original_session_date} at #{original_session_time} to #{session_date} at #{session_time}"
      end
    end
  end
end
