class TwilioWhatsappWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    return head :unauthorized unless valid_twilio_signature?

    result = Messaging::InboundWhatsappProcessor.new(params: webhook_params).call
    Rails.logger.info("Twilio WhatsApp webhook #{result.status}: #{result.reason}") unless result.accepted?

    head :ok
  end

  private

  def valid_twilio_signature?
    Messaging::TwilioSignatureVerifier.new.valid?(
      url: request.original_url,
      params: signature_params,
      signature: request.headers["X-Twilio-Signature"]
    )
  end

  def signature_params
    webhook_params
  end

  def webhook_params
    params.to_unsafe_h.except("controller", "action")
  end
end
