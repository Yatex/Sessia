module Messaging
  class Dispatcher
    def initialize(provider: nil)
      @provider = provider || Messaging::TwilioWhatsappProvider.new
    end

    def deliver(user:, client:, body:, session: nil, ai_task: nil, metadata: {})
      message = user.messages.create!(
        client: client,
        session: session,
        ai_task: ai_task,
        direction: "outbound",
        channel: Client::WHATSAPP_CHANNEL,
        status: "queued",
        subject: metadata["event"].presence || metadata[:event].presence || "Sessia message",
        body: body,
        metadata: metadata
      )

      return message unless provider.configured?

      delivery = provider.deliver(to: client.phone, body: body)
      message.update!(
        status: "sent",
        sent_at: Time.current,
        external_id: delivery[:external_id],
        metadata: message.metadata.merge("provider" => delivery[:provider])
      )
      message
    rescue StandardError => error
      if message&.persisted?
        message.update(status: "failed", error_message: error.message)
      end

      raise
    end

    private

    attr_reader :provider
  end
end
