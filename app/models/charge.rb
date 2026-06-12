class Charge < ApplicationRecord
  CURRENCIES = Session::CURRENCIES.freeze

  belongs_to :user
  belongs_to :client
  belongs_to :session, optional: true
  has_many :payments, dependent: :destroy
  has_many :credit_ledger_entries, foreign_key: :related_charge_id, dependent: :nullify, inverse_of: :related_charge

  enum status: {
    draft: 0,
    pending: 1,
    paid: 2,
    partially_paid: 3,
    overdue: 4,
    cancelled: 5,
    forgiven: 6
  }

  enum generated_by: {
    system: 0,
    manual: 1,
    session: 2,
    package: 3
  }, _prefix: :generated_by

  before_validation :normalize_currency
  before_validation :ensure_external_reference

  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :concept, presence: true, length: { maximum: 160 }
  validates :external_reference, presence: true, uniqueness: true
  validate :client_belongs_to_user
  validate :session_belongs_to_user

  scope :recent, -> { order(created_at: :desc) }
  scope :unpaid, -> { where(status: %i[draft pending partially_paid overdue]) }

  def amount
    amount_cents.to_i / 100.0
  end

  def approved_payment_total_cents
    payments.approved.sum(:amount_cents)
  end

  def payment_link_available?
    payment_url.present?
  end

  def recalculate_status!
    return sync_session_payment_status! if cancelled? || forgiven?

    approved_total = approved_payment_total_cents
    new_status =
      if approved_total >= amount_cents
        :paid
      elsif approved_total.positive?
        :partially_paid
      elsif due_date.present? && due_date < Date.current
        :overdue
      else
        :pending
      end

    attributes = { status: new_status }
    attributes[:paid_at] = Time.current if new_status == :paid && paid_at.blank?
    update!(attributes)
    sync_session_payment_status!
  end

  def sync_session_payment_status!
    Billing::RecalculateSessionPaymentStatusService.new(session).call if session.present?
  end

  private

  def normalize_currency
    self.currency = currency.to_s.strip.upcase.presence || "ARS"
  end

  def ensure_external_reference
    self.external_reference = "sessia-charge-#{SecureRandom.uuid}" if external_reference.blank?
  end

  def client_belongs_to_user
    return if client.blank? || user.blank?

    errors.add(:client, "must belong to your account") unless client.user_id == user_id
  end

  def session_belongs_to_user
    return if session.blank? || user.blank?

    errors.add(:session, "must belong to your account") unless session.user_id == user_id
  end
end
