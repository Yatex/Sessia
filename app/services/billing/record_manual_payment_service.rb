module Billing
  class RecordManualPaymentService
    def initialize(charge:, amount_cents:, paid_at: Time.current, method: "manual", note: nil, actor: nil)
      @charge = charge
      @amount_cents = amount_cents.to_i
      @paid_at = paid_at
      @method = method.to_s.presence || "manual"
      @note = note
      @actor = actor
    end

    def call
      raise ArgumentError, "Charge is required." if charge.blank?
      raise ArgumentError, "Amount must be positive." unless amount_cents.positive?

      Payment.transaction do
        payment = charge.payments.create!(
          user: charge.user,
          client: charge.client,
          provider: "manual",
          provider_payment_id: "manual-#{SecureRandom.uuid}",
          amount_cents: amount_cents,
          currency: charge.currency,
          status: "approved",
          status_detail: [method, note].compact_blank.join(" - "),
          paid_at: paid_at,
          raw_payload: {
            "source" => "professional_manual_entry",
            "method" => method,
            "note" => note
          }.compact
        )

        charge.recalculate_status!
        create_legacy_payment_record!(payment)
        AuditLog.record!(
          user: charge.user,
          actor: actor,
          event: "manual_payment_recorded",
          auditable: payment,
          metadata: { charge_id: charge.id, amount_cents: amount_cents, method: method }
        )
        payment
      end
    end

    private

    attr_reader :charge, :amount_cents, :paid_at, :method, :note, :actor

    def create_legacy_payment_record!(payment)
      return if charge.session.blank?

      charge.session.payment_records.create!(
        user: charge.user,
        client: charge.client,
        amount_cents: payment.amount_cents,
        currency: payment.currency,
        status: "paid",
        due_on: charge.due_date,
        paid_at: payment.paid_at,
        notes: "Manual #{method} payment#{note.present? ? ": #{note}" : ""}"
      )
    end
  end
end
