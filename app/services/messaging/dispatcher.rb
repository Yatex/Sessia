module Messaging
  class Dispatcher
    class TemplateValidationError < Messaging::TwilioWhatsappProvider::DeliveryError; end

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

      unless provider.configured?
        return message unless Rails.env.production?

        raise TemplateValidationError.new(
          "WhatsApp provider is not configured.",
          provider_metadata: { error_code: "provider_not_configured" }
        )
      end

      validation = validate_template!(template, required: delivery_metadata["whatsapp_template_required"])
      attempt = create_attempt(message, template: template, validation: validation)

      delivery = provider.deliver(to: client.phone, body: body, template: template)
      attempt.update!(
        status: "sent",
        retryable: false,
        provider_message_id: delivery[:external_id],
        response_data: delivery.deep_stringify_keys
      )
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
      ai_task&.update!(delivery_status: "sent", error_category: nil, next_retry_at: nil)
      message
    rescue StandardError => error
      classification = Ai::ErrorClassifier.call(error)
      if message&.persisted?
        metadata_updates = {}
        metadata_updates["provider"] = error.provider_metadata if error.respond_to?(:provider_metadata)
        message.update(
          status: "failed",
          error_message: error.message,
          metadata: metadata_updates.present? ? message.metadata.merge(metadata_updates) : message.metadata
        )
        attempt ||= create_attempt(message, template: template, validation: validation)
        attempt.update(
          status: "failed",
          error_category: classification.category,
          retryable: classification.retryable,
          next_retry_at: classification.retryable ? 2.minutes.from_now : nil,
          provider_error_code: error.respond_to?(:provider_metadata) ? error.provider_metadata.to_h[:error_code] || error.provider_metadata.to_h["error_code"] : nil,
          provider_error_message: error.message,
          response_data: error.respond_to?(:provider_metadata) ? error.provider_metadata : {}
        )
        ai_task&.update(
          delivery_status: classification.delivery_status,
          error_category: classification.category,
          last_error_at: Time.current,
          next_retry_at: classification.retryable ? 2.minutes.from_now : nil
        )
        create_configuration_alert(user: user, client: client, session: session, ai_task: ai_task, error: error, attempt: attempt) if classification.category == "provider_configuration"
      end

      raise
    end

    private

    attr_reader :provider

    def validate_template!(template, required:)
      if template.blank?
        return unless required
        raise TemplateValidationError.new("WhatsApp template validation failed: template is required.", provider_metadata: { error_code: "local_template_missing" })
      end

      result = Messaging::WhatsappTemplateValidator.new.call(template)
      return result if result.valid?

      raise TemplateValidationError.new(
        "WhatsApp template validation failed: #{result.errors.join(', ')}.",
        provider_metadata: result.debug.merge(error_code: "local_template_invalid", validation_errors: result.errors)
      )
    end

    def create_attempt(message, template:, validation: nil)
      message.delivery_attempts.create!(
        ai_task: message.ai_task,
        attempt_number: message.delivery_attempts.maximum(:attempt_number).to_i + 1,
        status: "pending",
        request_data: {
          template: template,
          validation: validation&.debug,
          body_mode: template.present? ? "content_template" : "free_form"
        }.compact
      )
    end

    def create_configuration_alert(user:, client:, session:, ai_task:, error:, attempt:)
      return if ai_task.blank?
      return if ai_task.ai_alerts.where("metadata ->> 'delivery_attempt_id' = ?", attempt.id.to_s).exists?

      user.ai_alerts.create!(
        client: client,
        session: session,
        ai_task: ai_task,
        severity: "high",
        title: "WhatsApp template configuration failed",
        body: error.message,
        metadata: { delivery_attempt_id: attempt.id, error_category: "provider_configuration" }
      )
    end

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
