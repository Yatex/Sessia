class CreditLedgerEntry < ApplicationRecord
  belongs_to :user
  belongs_to :client
  belongs_to :related_payment, class_name: "Payment", optional: true
  belongs_to :related_charge, class_name: "Charge", optional: true
  belongs_to :related_session, class_name: "Session", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum entry_type: {
    credit_added: 0,
    credit_used: 1,
    manual_adjustment: 2,
    refund: 3,
    correction: 4,
    package_purchase: 5,
    package_usage: 6
  }

  before_validation :normalize_currency

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :currency, presence: true, inclusion: { in: Session::CURRENCIES }
  validate :associations_belong_to_user

  scope :recent, -> { order(created_at: :desc) }

  private

  def normalize_currency
    self.currency = currency.to_s.strip.upcase.presence || "ARS"
  end

  def associations_belong_to_user
    return if user.blank?

    errors.add(:client, "must belong to your account") if client.present? && client.user_id != user_id
    errors.add(:payment, "must belong to your account") if related_payment.present? && related_payment.user_id != user_id
    errors.add(:charge, "must belong to your account") if related_charge.present? && related_charge.user_id != user_id
    errors.add(:session, "must belong to your account") if related_session.present? && related_session.user_id != user_id
    errors.add(:created_by, "must belong to your account") if created_by.present? && created_by_id != user_id
  end
end
