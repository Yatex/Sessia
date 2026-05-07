class PaymentRecord < ApplicationRecord
  belongs_to :user
  belongs_to :client, optional: true
  belongs_to :session, optional: true

  enum status: {
    pending: 0,
    paid: 1,
    overdue: 2,
    cancelled: 3
  }

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validate :client_belongs_to_user
  validate :session_belongs_to_user

  scope :recent, -> { order(created_at: :desc) }

  def amount
    amount_cents.to_i / 100.0
  end

  private

  def client_belongs_to_user
    return if client.blank? || user.blank?

    errors.add(:client, "must belong to your account") unless client.user_id == user_id
  end

  def session_belongs_to_user
    return if session.blank? || user.blank?

    errors.add(:session, "must belong to your account") unless session.user_id == user_id
  end
end
