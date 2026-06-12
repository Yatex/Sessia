module MercadoPago
  class CreatePreferenceService
    Result = Struct.new(:success?, :charge, :payment_url, :error_message, keyword_init: true)

    def initialize(charge:, success_url:, failure_url:, pending_url:, regenerate: false, client: nil)
      @charge = charge
      @success_url = success_url
      @failure_url = failure_url
      @pending_url = pending_url
      @regenerate = regenerate
      @client = client
    end

    def call
      return success(charge.payment_url) if charge.pending? && charge.payment_url.present? && !regenerate

      account = charge.user.mercado_pago_account
      unless account&.connected? && account.access_token.present?
        return failure("Mercado Pago account is not connected.")
      end

      response = api_client(account).create_preference(preference_payload)
      unless response.success?
        account.update!(status: "error", last_error: response.error_message)
        return failure(response.error_message)
      end

      body = response.body
      payment_url = MercadoPago::Client.sandbox? ? body["sandbox_init_point"] : body["init_point"]
      charge.update!(
        mercado_pago_preference_id: body["id"],
        mercado_pago_init_point: body["init_point"],
        mercado_pago_sandbox_init_point: body["sandbox_init_point"],
        payment_url: payment_url.presence || body["init_point"],
        status: charge.draft? ? "pending" : charge.status
      )
      success(charge.payment_url)
    end

    private

    attr_reader :charge, :success_url, :failure_url, :pending_url, :regenerate, :client

    def api_client(account)
      client || MercadoPago::Client.new(access_token: account.access_token)
    end

    def preference_payload
      {
        items: [
          {
            id: charge.external_reference,
            title: charge.concept,
            description: charge.description.to_s,
            quantity: 1,
            currency_id: charge.currency,
            unit_price: charge.amount
          }
        ],
        external_reference: charge.external_reference,
        notification_url: notification_url,
        back_urls: {
          success: success_url,
          failure: failure_url,
          pending: pending_url
        },
        auto_return: "approved",
        metadata: {
          charge_id: charge.id,
          client_id: charge.client_id,
          session_id: charge.session_id,
          user_id: charge.user_id,
          app_name: "sessia"
        }.compact
      }
    end

    def notification_url
      host = ENV["APP_HOST"].to_s.delete_suffix("/").presence || "http://localhost:3000"
      "#{host}/webhooks/mercado_pago"
    end

    def success(payment_url)
      Result.new(success?: true, charge: charge, payment_url: payment_url)
    end

    def failure(message)
      Result.new(success?: false, charge: charge, error_message: message)
    end
  end
end
