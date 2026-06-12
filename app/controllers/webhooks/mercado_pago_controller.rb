module Webhooks
  class MercadoPagoController < ActionController::API
    def create
      unless MercadoPago::SignatureVerifier.new(headers: request.headers, params: params).valid?
        render json: { error: "invalid_signature" }, status: :unauthorized
        return
      end

      result = MercadoPago::WebhookProcessor.new(params: params).call
      if result.success?
        render json: { ok: true, ignored: result.ignored.present? }
      else
        render json: { error: result.error_message }, status: :unprocessable_entity
      end
    end
  end
end
