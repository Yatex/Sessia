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
      process_with_ai(message) if was_new

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
      Result.new(status: :accepted, message: message, client: message.client, reason: "Delivery status updated to #{provider_status}.")
    end

    def resolve_client
      return if normalized_from.blank?

      candidates = Client.includes(:user, user: :ai_setting).where(phone_normalized: normalized_from).to_a
      return candidates.first if candidates.one?
      return if candidates.empty?

      candidates.find { |client| professional_number_matches?(client) }
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
