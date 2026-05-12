class Subscription < ApplicationRecord
  belongs_to :user

  PLAN_TIERS = %w[trial starter pro studio].freeze
  FREE_TRIAL_DAYS = 14

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
  scope :free_trials, -> { where(provider: "trial") }

  def self.create_free_trial_for!(user)
    return if user.subscriptions.free_trials.exists?

    user.subscriptions.create!(
      plan_tier: "trial",
      status: "trialing",
      provider: "trial",
      provider_plan_id: "trial_#{FREE_TRIAL_DAYS}_days",
      current_period_start: Time.current,
      current_period_end: FREE_TRIAL_DAYS.days.from_now,
      trial_ends_at: FREE_TRIAL_DAYS.days.from_now,
      quantity: 1
    )
  end

  def usable?
    (active? || trialing?) && (current_period_end.blank? || current_period_end.future?) ||
      (cancelled? && current_period_end.present? && current_period_end.future?)
  end

  def period_label
    return "Free trial until #{trial_ends_at.to_date.to_fs(:long)}" if provider == "trial" && trial_ends_at.present?
    return "Renews #{current_period_end.to_date.to_fs(:long)}" if active? && current_period_end.present?
    return "Access until #{current_period_end.to_date.to_fs(:long)}" if cancelled? && current_period_end.present?

    status.humanize
  end
end
