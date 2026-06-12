module Billing
  class RecalculateSessionPaymentStatusService
    def initialize(session)
      @session = session
    end

    def call
      return if session.blank?

      charge = session.main_charge
      return if charge.blank?

      session.update!(payment_status: mapped_status(charge))
    end

    private

    attr_reader :session

    def mapped_status(charge)
      case charge.status
      when "paid"
        "paid"
      when "partially_paid"
        "partially_paid"
      when "overdue"
        "overdue"
      when "cancelled"
        "cancelled"
      when "forgiven"
        "waived"
      else
        "pending"
      end
    end
  end
end
