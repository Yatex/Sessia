class Subscription < ApplicationRecord
  belongs_to :user

  PLAN_TIERS = %w[starter pro studio].freeze

  enum status: {
    pending: 0,
    trialing: 1,
    active: 2,
    past_due: 3,
    cancelled: 4,
    expired: 5
  }

  validates :plan_tier, inclusion: { in: PLAN_TIERS }
  validates :provider, presence: true
  validates :quantity, numericality: { greater_than: 0 }

  scope :active_or_trialing, -> { where(status: %i[active trialing]) }
  scope :stripe_backed, -> { where(provider: "stripe") }
  scope :admin_granted, -> { where(provider: "admin") }

  def usable?
    active? || trialing? || (cancelled? && current_period_end.present? && current_period_end.future?)
  end

  def period_label
    return "Renews #{current_period_end.to_date.to_fs(:long)}" if active? && current_period_end.present?
    return "Access until #{current_period_end.to_date.to_fs(:long)}" if cancelled? && current_period_end.present?

    status.humanize
  end
end
