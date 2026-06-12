class ClientBillingProfile < ApplicationRecord
  CURRENCIES = Session::CURRENCIES.freeze

  belongs_to :client
  belongs_to :user

  enum default_due_timing: {
    same_day: 0,
    before_session: 1,
    after_session: 2,
    custom: 3
  }

  before_validation :normalize_currency

  validates :client_id, uniqueness: true
  validates :default_session_price_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :custom_due_days_before, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validate :client_belongs_to_user

  def default_session_price
    default_session_price_cents.to_i / 100.0
  end

  def default_session_price=(value)
    normalized = value.to_s.strip
    self.default_session_price_cents =
      if normalized.blank?
        0
      else
        (BigDecimal(normalized.tr(",", ".")) * 100).round
      end
  rescue ArgumentError
    self.default_session_price_cents = 0
  end

  private

  def normalize_currency
    self.currency = currency.to_s.strip.upcase.presence || "ARS"
  end

  def client_belongs_to_user
    return if client.blank? || user.blank?

    errors.add(:client, "must belong to your account") unless client.user_id == user_id
  end
end
