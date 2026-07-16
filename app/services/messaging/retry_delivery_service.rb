module Messaging
  class RetryDeliveryService
    def initialize(message:, provider: Messaging::TwilioWhatsappProvider.new)
      @message, @provider = message, provider
    end

    def call
      task = message.ai_task
      return message unless task&.claim_delivery_retry!

      template = message.metadata.to_h["whatsapp_template"]
      validation = template.present? ? Messaging::WhatsappTemplateValidator.new.call(template) : nil
      raise "WhatsApp template validation failed during retry." if validation && !validation.valid?

      attempt = message.delivery_attempts.create!(
        ai_task: task,
        attempt_number: message.delivery_attempts.maximum(:attempt_number).to_i + 1,
        status: "pending",
        request_data: { template: template, retry: true }
      )
      delivery = provider.deliver(to: message.client.phone, body: message.body, template: template)
      attempt.update!(status: "sent", provider_message_id: delivery[:external_id], response_data: delivery.deep_stringify_keys)
      message.update!(status: "sent", sent_at: Time.current, external_id: delivery[:external_id], error_message: nil)
      task.update!(delivery_status: "sent", error_category: nil, next_retry_at: nil)
      message
    rescue StandardError => error
      classification = Ai::ErrorClassifier.call(error)
      attempt&.update!(status: "failed", error_category: classification.category, retryable: classification.retryable, provider_error_message: error.message)
      task&.increment!(:retry_count)
      exhausted = task && task.retry_count >= AiTask::MAX_RETRIES
      task&.update!(
        delivery_status: exhausted ? "failed_permanent" : classification.delivery_status,
        error_category: exhausted ? "provider_permanent" : classification.category,
        next_retry_at: classification.retryable && !exhausted ? Time.current + (2**task.retry_count).minutes : nil,
        last_error_at: Time.current
      )
      message
    end

    private

    attr_reader :message, :provider
  end
end
