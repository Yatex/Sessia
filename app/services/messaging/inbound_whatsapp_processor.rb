module Messaging
  class InboundWhatsappProcessor
    Result = Struct.new(:status, :message, :client, :reason, keyword_init: true) do
      def accepted?
        status == :accepted
      end
    end

    def initialize(params:, ai_processor: Ai::InboundMessageProcessor)
      @params = params.to_h.stringify_keys
      @ai_processor = ai_processor
    end

    def call
      return handle_delivery_status_callback if delivery_status_callback?

      client = resolve_client
      return Result.new(status: :ignored, reason: "No Sessia client matches #{from_address}.") if client.blank?
      return Result.new(status: :ignored, client: client, reason: "Inbound message has no body.") if message_body.blank?

      message, was_new = persist_message(client)
      handle_new_message(message) if was_new

      Result.new(status: :accepted, message: message, client: client)
    end

    private

    attr_reader :params, :ai_processor

    def delivery_status_callback?
      provider_status.present? && message_sid.present? && message_body.blank?
    end

    def handle_delivery_status_callback
      message = Message.outbound.find_by(external_id: message_sid)
      return Result.new(status: :ignored, reason: "No outbound Sessia message matches #{message_sid}.") if message.blank?

      metadata = message.metadata.deep_dup
      existing_provider_metadata = metadata["provider"].is_a?(Hash) ? metadata["provider"] : { "name" => metadata["provider"].presence }.compact
      provider_metadata = existing_provider_metadata.merge(
        "name" => "twilio_whatsapp",
        "status" => provider_status,
        "error_code" => provider_error_code,
        "error_message" => provider_error_message
      ).compact

      attributes = {
        metadata: metadata.merge("provider" => provider_metadata)
      }

      if provider_status.in?(%w[failed undelivered])
        attributes[:status] = "failed"
        attributes[:error_message] = provider_error_message.presence || "Twilio WhatsApp delivery #{provider_status}."
      elsif provider_status.in?(%w[sent delivered read])
        attributes[:status] = "sent"
        attributes[:sent_at] = message.sent_at || Time.current
        attributes[:error_message] = nil
      end

      message.update!(attributes)
      update_delivery_pipeline(message)
      Result.new(status: :accepted, message: message, client: message.client, reason: "Delivery status updated to #{provider_status}.")
    end

    def resolve_client
      return if normalized_from.blank?

      candidates = Client.includes(:user, user: :ai_setting).where(phone_normalized: normalized_from).to_a
      return candidates.first if candidates.one?
      return if candidates.empty?

      candidates.find { |client| professional_number_matches?(client) }
    end

    def update_delivery_pipeline(message)
      task = message.ai_task
      attempt = message.delivery_attempts.order(:attempt_number).last
      if provider_status.in?(%w[sent delivered read])
        normalized = provider_status.in?(%w[delivered read]) ? "delivered" : "sent"
        attempt&.update!(status: normalized, retryable: false, provider_message_id: message_sid, response_data: params.slice("MessageStatus", "SmsStatus"))
        task&.update!(delivery_status: normalized, error_category: nil, next_retry_at: nil)
      elsif provider_status.in?(%w[failed undelivered])
        error = Messaging::TwilioWhatsappProvider::DeliveryError.new(
          provider_error_message.presence || "Twilio delivery failed.",
          provider_metadata: { error_code: provider_error_code, error_message: provider_error_message }
        )
        classification = Ai::ErrorClassifier.call(error)
        attempt&.update!(status: "failed", error_category: classification.category, retryable: classification.retryable, provider_error_code: provider_error_code, provider_error_message: provider_error_message)
        task&.update!(delivery_status: classification.delivery_status, error_category: classification.category, last_error_at: Time.current, next_retry_at: classification.retryable ? 2.minutes.from_now : nil)
      end
      trace = task&.ai_traces&.order(created_at: :desc)&.first
      trace&.update!(delivery_status: task.delivery_status, error_category: task.error_category, delivery_result: message.metadata.to_h["provider"] || {})
    end

    def professional_number_matches?(client)
      professional_number = client.user.ai_setting&.professional_whatsapp_phone
      Messaging::WhatsappAddress.same?(professional_number, to_address)
    end

    def persist_message(client)
      message = find_existing_message(client) || client.messages.new
      was_new = message.new_record?

      message.assign_attributes(
        user: client.user,
        session: related_session(client),
        direction: "inbound",
        channel: Client::WHATSAPP_CHANNEL,
        status: "sent",
        subject: "WhatsApp reply",
        body: message_body,
        sent_at: Time.current,
        external_id: message_sid.presence,
        metadata: message_metadata
      )
      message.save!
      client.mark_linked!
      [message, was_new]
    end

    def find_existing_message(client)
      return if message_sid.blank?

      client.user.messages.find_by(external_id: message_sid)
    end

    def process_with_ai(message)
      ai_processor.new(message: message).call
    rescue StandardError => error
      Rails.logger.warn("Inbound WhatsApp AI processing skipped for message #{message.id}: #{error.class}: #{error.message}")
    end

    def handle_new_message(message)
      if client_connection_message?(message.body)
        mark_connection_message!(message)
      else
        process_with_ai(message)
      end
    end

    def client_connection_message?(body)
      normalized = normalize_text(body)
      return false if normalized.blank?

      normalized.include?("sessia") &&
        normalized.match?(/\b(connect my sessions|want to connect my sessions|conectar mis sesiones|conectar mis clases)\b/)
    end

    def mark_connection_message!(message)
      metadata = message.metadata.to_h.deep_dup
      message.update!(
        subject: "WhatsApp connected",
        metadata: metadata.merge(
          "event" => "client_connected",
          "ai_processing" => "skipped_connection_message"
        )
      )
    end

    def normalize_text(value)
      I18n.transliterate(value.to_s.downcase).squish
    end

    def related_session(client)
      recent_outbound_session(client) ||
        next_upcoming_session(client) ||
        recent_past_session(client)
    end

    def recent_outbound_session(client)
      client.messages
        .outbound
        .where.not(session_id: nil)
        .where("created_at >= ?", 14.days.ago)
        .includes(:session)
        .recent_first
        .map(&:session)
        .find(&:present?)
    end

    def next_upcoming_session(client)
      client.sessions
        .where("end_time >= ?", Time.current)
        .chronological
        .first
    end

    def recent_past_session(client)
      client.sessions
        .where(end_time: 7.days.ago..Time.current)
        .order(end_time: :desc)
        .first
    end

    def message_metadata
      {
        "source" => "twilio_whatsapp",
        "twilio" => {
          "message_sid" => message_sid.presence,
          "sms_sid" => params["SmsSid"].presence,
          "account_sid" => params["AccountSid"].presence,
          "from" => from_address.presence,
          "to" => to_address.presence,
          "profile_name" => params["ProfileName"].presence,
          "wa_id" => params["WaId"].presence,
          "num_media" => params["NumMedia"].presence
        }.compact
      }
    end

    def message_body
      params["Body"].to_s.strip.presence || media_placeholder
    end

    def media_placeholder
      return unless params["NumMedia"].to_i.positive?

      "Media message received."
    end

    def message_sid
      params["MessageSid"].presence || params["SmsMessageSid"].presence || params["SmsSid"].presence
    end

    def provider_status
      params["MessageStatus"].presence || params["SmsStatus"].presence || params["DeliveryStatus"].presence
    end

    def provider_error_message
      params["ErrorMessage"].presence || params["ErrorText"].presence
    end

    def provider_error_code
      params["ErrorCode"].presence
    end

    def from_address
      params["From"].to_s
    end

    def to_address
      params["To"].to_s
    end

    def normalized_from
      Messaging::WhatsappAddress.normalize(from_address)
    end
  end
end
