module Messaging
  class WhatsappTemplateCatalog
    Definition = Data.define(:key, :locale, :friendly_name, :category, :body, :variables, :env_key, :workflow) do
      def placeholder_numbers = body.scan(/\{\{(\d+)\}\}/).flatten
      def expected_numbers = (1..variables.length).map(&:to_s)
      def content_sid = ENV[env_key].to_s.strip.presence

      def default_variables
        variables.each_with_index.to_h do |name, index|
          [(index + 1).to_s, sample_values.fetch(name).fetch(locale)]
        end
      end

      def to_h
        {
          key: key, locale: locale, friendly_name: friendly_name, category: category,
          body: body, variables: variables, placeholders: placeholder_numbers,
          env_key: env_key, workflow: workflow, content_sid: content_sid
        }
      end

      private

      def sample_values
        {
          client_name: { es: "María", en: "Maria" },
          session_name: { es: "Terapia", en: "Therapy" },
          session_date: { es: "15 de agosto", en: "August 15" },
          session_time: { es: "10:00", en: "10:00 AM" },
          payment_amount: { es: "ARS 25.000", en: "USD 25.00" },
          schedule_change_detail: {
            es: "la sesión pasó al 16 de agosto a las 11:00",
            en: "the session moved to August 16 at 11:00 AM"
          }
        }
      end
    end

    Template = Data.define(:key, :locale, :content_sid, :variable_names, :semantic_variables, :variables) do
      def name = "#{key}_#{locale}"

      def to_h
        {
          key: key, name: name, locale: locale, content_sid: content_sid,
          variable_names: variable_names, semantic_variables: semantic_variables,
          variables: variables
        }
      end
    end

    WORKFLOWS = {
      "confirm_session" => :session_confirmation,
      "follow_up_no_response" => :session_follow_up,
      "payment_reminder" => :payment_reminder,
      "send_pre_session_reminder" => :session_reminder,
      "ask_feedback_after_session" => :session_feedback,
      "blocked_time_rebooking" => :session_change
    }.freeze

    CONTRACTS = {
      session_confirmation: {
        workflow: "confirm_session",
        variables: %i[client_name session_name session_date session_time],
        bodies: {
          es: "Hola {{1}}, ¿podés confirmar tu sesión de {{2}} del {{3}} a las {{4}}?",
          en: "Hi {{1}}, can you confirm your {{2}} session on {{3}} at {{4}}?"
        }
      },
      session_follow_up: {
        workflow: "follow_up_no_response",
        variables: %i[client_name session_name session_date session_time],
        bodies: {
          es: "Hola {{1}}, todavía necesitamos confirmar tu sesión de {{2}} del {{3}} a las {{4}}. ¿Podés responder si asistís?",
          en: "Hi {{1}}, we still need to confirm your {{2}} session on {{3}} at {{4}}. Can you let us know if you will attend?"
        }
      },
      session_reminder: {
        workflow: "send_pre_session_reminder",
        variables: %i[client_name session_name session_date session_time],
        bodies: {
          es: "Hola {{1}}, te recordamos tu sesión de {{2}} del {{3}} a las {{4}}.",
          en: "Hi {{1}}, this is a reminder for your {{2}} session on {{3}} at {{4}}."
        }
      },
      session_feedback: {
        workflow: "ask_feedback_after_session",
        variables: %i[client_name session_name session_date session_time],
        bodies: {
          es: "Hola {{1}}, ¿cómo estuvo tu sesión de {{2}} del {{3}} a las {{4}}? Tu opinión nos ayuda a mejorar.",
          en: "Hi {{1}}, how was your {{2}} session on {{3}} at {{4}}? Your feedback helps us improve."
        }
      },
      payment_reminder: {
        workflow: "payment_reminder",
        variables: %i[client_name payment_amount session_name],
        bodies: {
          es: "Hola {{1}}, está pendiente el pago de {{2}} por tu sesión de {{3}}. Si ya pagaste, la acreditación puede demorar unos minutos.",
          en: "Hi {{1}}, payment of {{2}} for your {{3}} session is still pending. If you already paid, confirmation may take a few minutes."
        }
      },
      session_change: {
        workflow: "blocked_time_rebooking",
        variables: %i[client_name session_name schedule_change_detail],
        bodies: {
          es: "Hola {{1}}, necesitamos cambiar tu sesión de {{2}}: {{3}}. Respondé este mensaje para coordinar una nueva opción.",
          en: "Hi {{1}}, we need to change your {{2}} session: {{3}}. Reply to this message so we can arrange another option."
        }
      },
      session_canceled: {
        workflow: "blocked_time_rebooking (cancelled session)",
        variables: %i[client_name session_name session_date session_time],
        bodies: {
          es: "Hola {{1}}, tu sesión de {{2}} del {{3}} a las {{4}} fue cancelada. Respondé este mensaje para coordinar una nueva fecha.",
          en: "Hi {{1}}, your {{2}} session on {{3}} at {{4}} was cancelled. Reply to this message to arrange a new date."
        }
      }
    }.freeze

    class << self
      def definitions
        @definitions ||= CONTRACTS.flat_map do |key, contract|
          contract.fetch(:bodies).map do |locale, body|
            Definition.new(
              key,
              locale,
              "sessia_#{key}_#{locale}_v1",
              "UTILITY",
              body,
              contract.fetch(:variables),
              "TWILIO_TEMPLATE_#{key.to_s.upcase}_#{locale.to_s.upcase}",
              contract.fetch(:workflow)
            )
          end
        end.freeze
      end

      def fetch(key, locale)
        definitions.find { |definition| definition.key == key.to_sym && definition.locale == locale.to_sym } ||
          raise(KeyError, "Unknown WhatsApp template #{key}/#{locale}")
      end

      def env_block(sids = {})
        definitions.map do |definition|
          sid = sids.fetch([definition.key, definition.locale], definition.content_sid)
          "#{definition.env_key}=#{sid}"
        end.join("\n")
      end
    end

    def initialize(user:, client:, session: nil, ai_task: nil)
      @user, @client, @session, @ai_task = user, client, session, ai_task
    end

    def template
      key = template_key
      return if key.blank?

      definition = self.class.fetch(key, language)
      names = definition.variables
      semantic = semantic_values.slice(*names)
      numbered = names.each_with_index.to_h { |name, index| [(index + 1).to_s, semantic[name]] }
      Template.new(key, definition.locale, definition.content_sid, names, semantic, numbered)
    end

    private

    attr_reader :user, :client, :session, :ai_task

    def template_key
      key = WORKFLOWS[ai_task&.automation_key.to_s]
      key = :session_canceled if key == :session_change && session&.cancelled?
      key
    end

    def language = (user&.locale.to_s.presence_in(%w[en es]) || User::DEFAULT_LOCALE).to_sym

    def semantic_values
      {
        client_name: client&.name.to_s.presence || fallback("client", "cliente"),
        session_name: session&.title.to_s.presence || fallback("the session", "la sesión"),
        session_date: localized(session_start.to_date, :long),
        session_time: localized(session_start, :short_time),
        payment_amount: payment_amount,
        schedule_change_detail: schedule_change_detail
      }
    end

    def session_start = (session&.start_time || Time.current).in_time_zone(user_time_zone)
    def user_time_zone = user&.time_zone.presence || Time.zone.name
    def localized(value, format) = I18n.with_locale(language) { I18n.l(value, format: format) }
    def fallback(en, es) = language == :es ? es : en

    def original_session_start
      Time.zone.parse(ai_task&.context_data.to_h["original_start_time"].to_s)&.in_time_zone(user_time_zone)
    rescue ArgumentError, TypeError
      nil
    end

    def payment_amount
      return fallback("the pending amount", "el monto pendiente") if session.blank? || session.price_cents.to_i.zero?
      format("%s %.2f", session.currency.presence || "USD", session.price_cents.to_i / 100.0)
    end

    def schedule_change_detail
      original = original_session_start || session_start
      if language == :es
        "la sesión pasó del #{localized(original.to_date, :long)} a las #{localized(original, :short_time)} al #{localized(session_start.to_date, :long)} a las #{localized(session_start, :short_time)}"
      else
        "the session moved from #{localized(original.to_date, :long)} at #{localized(original, :short_time)} to #{localized(session_start.to_date, :long)} at #{localized(session_start, :short_time)}"
      end
    end
  end
end
