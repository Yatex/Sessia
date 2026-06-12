module MercadoPago
  class WebhookProcessor
    Result = Struct.new(:success?, :charge, :payment, :ignored, :error_message, keyword_init: true)

    def initialize(params:, client: nil)
      @params = params.to_h.deep_stringify_keys
      @client = client
    end

    def call
      payment_id = webhook_payment_id
      return ignored("Webhook does not include a payment id.") if payment_id.blank?

      response = fetch_payment(payment_id)
      return failure(response.error_message) unless response.success?

      payload = response.body
      charge = find_charge(payload)
      return ignored("No Sessia charge matches Mercado Pago payment #{payment_id}.") if charge.blank?

      payment = upsert_payment!(charge, payload)
      charge.recalculate_status!
      handle_overpayment!(charge, payment) if payment.approved?
      AuditLog.record!(
        user: charge.user,
        event: "payment_confirmed_by_webhook",
        auditable: payment,
        metadata: { charge_id: charge.id, provider_payment_id: payment.provider_payment_id, status: payment.status }
      ) if payment.approved?

      Result.new(success?: true, charge: charge, payment: payment)
    rescue StandardError => error
      failure(error.message)
    end

    private

    attr_reader :params, :client

    def fetch_payment(payment_id)
      return client.payment(payment_id) if client.present?

      accounts = PaymentAccount.connected.where(provider: PaymentAccount::PROVIDER_MERCADO_PAGO).to_a
      accounts.each do |account|
        response = MercadoPago::Client.new(access_token: account.access_token).payment(payment_id)
        return response if response.success?
      end

      MercadoPago::Client::Response.new(success?: false, status: nil, body: {}, error_message: "Mercado Pago payment could not be fetched with any connected account.")
    end

    def webhook_payment_id
      params.dig("data", "id").presence ||
        params["data.id"].presence ||
        params["id"].presence ||
        params["payment_id"].presence
    end

    def find_charge(payload)
      external_reference = payload["external_reference"].presence
      metadata = payload["metadata"].is_a?(Hash) ? payload["metadata"] : {}
      preference_id = payload["preference_id"].presence

      Charge.find_by(external_reference: external_reference) ||
        Charge.find_by(id: metadata["charge_id"]) ||
        Charge.find_by(mercado_pago_preference_id: preference_id)
    end

    def upsert_payment!(charge, payload)
      provider_payment_id = payload["id"].to_s
      amount_cents = decimal_to_cents(payload["transaction_amount"] || payload["transaction_details"]&.dig("total_paid_amount"))
      status = map_status(payload["status"])

      payment = Payment.find_or_initialize_by(provider: "mercado_pago", provider_payment_id: provider_payment_id)
      payment.assign_attributes(
        charge: charge,
        user: charge.user,
        client: charge.client,
        amount_cents: amount_cents,
        currency: payload["currency_id"].presence || charge.currency,
        status: status,
        status_detail: payload["status_detail"].presence,
        paid_at: approved_paid_at(payload),
        raw_payload: payload
      )
      payment.save!
      payment
    end

    def approved_paid_at(payload)
      return unless map_status(payload["status"]) == "approved"

      Time.zone.parse(payload["date_approved"].to_s)
    rescue ArgumentError, TypeError
      Time.current
    end

    def map_status(status)
      case status.to_s
      when "approved"
        "approved"
      when "rejected"
        "rejected"
      when "cancelled"
        "cancelled"
      when "refunded"
        "refunded"
      when "charged_back"
        "charged_back"
      when "in_process", "in_mediation"
        "in_process"
      else
        "pending"
      end
    end

    def handle_overpayment!(charge, payment)
      overpaid_cents = charge.approved_payment_total_cents - charge.amount_cents
      return unless overpaid_cents.positive?
      return if CreditLedgerEntry.exists?(related_payment: payment, related_charge: charge, entry_type: "credit_added")

      CreditLedgerEntry.create!(
        user: charge.user,
        client: charge.client,
        amount_cents: overpaid_cents,
        currency: charge.currency,
        entry_type: "credit_added",
        reason: "Mercado Pago overpayment",
        related_payment: payment,
        related_charge: charge,
        related_session: charge.session
      )
    end

    def decimal_to_cents(value)
      (BigDecimal(value.to_s) * 100).round
    rescue ArgumentError
      0
    end

    def ignored(message)
      Result.new(success?: true, ignored: true, error_message: message)
    end

    def failure(message)
      Result.new(success?: false, error_message: message)
    end
  end
end
