module Messaging
  class Dispatcher
    def initialize(provider: nil)
      @provider = provider || Messaging::TwilioWhatsappProvider.new
    end

    def deliver(user:, client:, body:, session: nil, ai_task: nil, metadata: {})
      delivery_metadata = metadata.deep_stringify_keys
      template = whatsapp_template_for(user: user, client: client, session: session, ai_task: ai_task, metadata: delivery_metadata)
      delivery_metadata["whatsapp_template"] = template if template.present?
      delivery_metadata["whatsapp_template_required"] = true if template_required?(client: client, ai_task: ai_task)

      message = user.messages.create!(
        client: client,
        session: session,
        ai_task: ai_task,
        direction: "outbound",
        channel: Client::WHATSAPP_CHANNEL,
        status: "queued",
        subject: delivery_metadata["event"].presence || "Sessia message",
        body: body,
        metadata: delivery_metadata
      )

      return message unless provider.configured?

      delivery = provider.deliver(to: client.phone, body: body, template: template)
      message.update!(
        status: "sent",
        sent_at: Time.current,
        external_id: delivery[:external_id],
        metadata: message.metadata.merge(
          "provider" => {
            "name" => delivery[:provider],
            "status" => delivery[:status],
            "error_code" => delivery[:error_code],
            "error_message" => delivery[:error_message]
          }.compact
        )
      )
      message
    rescue StandardError => error
      if message&.persisted?
        metadata_updates = {}
        metadata_updates["provider"] = error.provider_metadata if error.respond_to?(:provider_metadata)
        message.update(
          status: "failed",
          error_message: error.message,
          metadata: metadata_updates.present? ? message.metadata.merge(metadata_updates) : message.metadata
        )
      end

      raise
    end

    private

    attr_reader :provider

    def whatsapp_template_for(user:, client:, session:, ai_task:, metadata:)
      explicit_template = metadata["whatsapp_template"]
      return explicit_template if explicit_template.present?
      return unless template_required?(client: client, ai_task: ai_task)

      Messaging::WhatsappTemplateCatalog.new(
        user: user,
        client: client,
        session: session,
        ai_task: ai_task
      ).template&.to_h&.deep_stringify_keys
    end

    def template_required?(client:, ai_task:)
      return false if ai_task.blank?
      return false if ai_task.trigger_event == "client_replied"

      !conversation_window_open?(client)
    end

    def conversation_window_open?(client)
      client.messages.inbound.where("created_at >= ?", 24.hours.ago).exists?
    end
  end
end
