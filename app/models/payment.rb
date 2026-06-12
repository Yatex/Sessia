class Payment < ApplicationRecord
  belongs_to :charge
  belongs_to :client
  belongs_to :user
  has_many :credit_ledger_entries, foreign_key: :related_payment_id, dependent: :nullify, inverse_of: :related_payment

  enum status: {
    pending: 0,
    approved: 1,
    rejected: 2,
    cancelled: 3,
    refunded: 4,
    charged_back: 5,
    in_process: 6
  }

  before_validation :normalize_provider
  before_validation :normalize_currency

  validates :provider, presence: true
  validates :provider_payment_id, uniqueness: { scope: :provider }, allow_blank: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :currency, presence: true, inclusion: { in: Session::CURRENCIES }
  validate :associations_belong_to_user

  scope :recent, -> { order(created_at: :desc) }

  def amount
    amount_cents.to_i / 100.0
  end

  private

  def normalize_provider
    self.provider = provider.to_s.presence || "mercado_pago"
  end

  def normalize_currency
    self.currency = currency.to_s.strip.upcase.presence || "ARS"
  end

  def associations_belong_to_user
    return if user.blank?

    errors.add(:charge, "must belong to your account") if charge.present? && charge.user_id != user_id
    errors.add(:client, "must belong to your account") if client.present? && client.user_id != user_id
  end
end
