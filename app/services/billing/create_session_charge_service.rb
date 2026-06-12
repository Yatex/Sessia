module Billing
  class CreateSessionChargeService
    def initialize(session)
      @session = session
    end

    def call
      return if session.blank? || session.price_cents.to_i <= 0
      return session.main_charge if session.main_charge.present?

      charge = session.user.charges.create!(
        client: session.client,
        session: session,
        amount_cents: session.price_cents.to_i,
        currency: session.currency.presence || "ARS",
        concept: concept,
        description: description,
        due_date: due_date,
        status: "pending",
        generated_by: "session"
      )
      session.update!(charge: charge, payment_status: "pending")
      AuditLog.record!(user: session.user, event: "session_charge_created", auditable: charge, metadata: { session_id: session.id })
      charge
    end

    private

    attr_reader :session

    def concept
      "Sessia - Session on #{session.start_time.to_date.iso8601}"
    end

    def description
      [session.client.name, session.title].compact_blank.join(" - ")
    end

    def due_date
      if session.payment_required_before_session?
        session.start_time.to_date - 1.day
      else
        session.start_time.to_date
      end
    end
  end
end
