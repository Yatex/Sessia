class Session < ApplicationRecord
  belongs_to :user
  belongs_to :client
  belongs_to :parent_session, class_name: "Session", optional: true
  belongs_to :charge, optional: true
  has_many :generated_sessions, class_name: "Session", foreign_key: :parent_session_id, dependent: :destroy, inverse_of: :parent_session
  has_many :payment_records, dependent: :nullify
  has_one :session_charge, class_name: "Charge", dependent: :nullify, inverse_of: :session
  has_many :messages, dependent: :nullify
  has_many :ai_tasks, dependent: :nullify
  has_many :ai_alerts, dependent: :nullify

  RECURRENCE_FREQUENCIES = %w[none weekly monthly].freeze
  CURRENCIES = %w[ARS UYU USD EUR GBP BRL CLP].freeze
  RECURRENCE_WEEKDAYS = [
    ["Sunday", 0],
    ["Monday", 1],
    ["Tuesday", 2],
    ["Wednesday", 3],
    ["Thursday", 4],
    ["Friday", 5],
    ["Saturday", 6]
  ].freeze

  enum status: {
    scheduled: 0,
    completed: 1,
    cancelled: 2,
    no_show: 3
  }

  enum confirmation_status: {
    not_requested: 0,
    pending: 1,
    confirmed: 2,
    declined: 3,
    maybe: 4
  }, _prefix: :confirmation

  enum payment_status: {
    not_tracked: 0,
    pending: 1,
    paid: 2,
    overdue: 3,
    cancelled: 4,
    partially_paid: 5,
    waived: 6,
    refunded: 7
  }, _prefix: :payment

  before_validation :normalize_currency
  before_validation :normalize_recurrence

  validates :title, presence: true, length: { maximum: 140 }
  validates :start_time, :end_time, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :recurrence_frequency, inclusion: { in: RECURRENCE_FREQUENCIES }
  validate :end_time_after_start_time
  validate :client_belongs_to_user
  validate :parent_session_belongs_to_user
  validate :recurrence_ends_after_start

  scope :chronological, -> { order(:start_time, :end_time) }
  scope :for_week, ->(date) {
    start_date = date.to_date.beginning_of_week(:monday)
    where(start_time: start_date.beginning_of_day..(start_date + 6.days).end_of_day)
  }
  scope :needing_follow_up, -> {
    where(status: :completed).or(where(confirmation_status: :pending)).or(where(payment_status: :overdue))
  }

  def duration_minutes
    return 0 if start_time.blank? || end_time.blank?

    ((end_time - start_time) / 60).round
  end

  def price
    price_cents.to_i / 100.0
  end

  def price=(value)
    normalized = value.to_s.strip
    self.price_cents =
      if normalized.blank?
        0
      else
        (BigDecimal(normalized.tr(",", ".")) * 100).round
      end
  rescue ArgumentError
    self.price_cents = 0
  end

  def priced?
    price_cents.to_i.positive?
  end

  def payment_attention?
    payment_pending? || payment_overdue? || payment_partially_paid?
  end

  def needs_follow_up?
    completed? || confirmation_pending? || payment_overdue?
  end

  def recurring_series?
    recurring? && parent_session_id.blank?
  end

  def generated_occurrence?
    parent_session_id.present?
  end

  def main_charge
    charge || session_charge
  end

  def mark_paid!(paid_at: Time.current)
    target_charge = main_charge || Billing::CreateSessionChargeService.new(self).call
    if target_charge.blank?
      return update!(payment_status: :paid)
    end

    Billing::RecordManualPaymentService.new(
      charge: target_charge,
      amount_cents: target_charge.amount_cents,
      paid_at: paid_at,
      method: "manual",
      note: "Marked paid by professional."
    ).call
  end

  private

  def normalize_currency
    self.currency = currency.to_s.strip.upcase.presence || "ARS"
  end

  def normalize_recurrence
    self.recurrence_frequency = recurrence_frequency.to_s.presence || "none"
    self.recurrence_days = Array(recurrence_days).reject(&:blank?).map(&:to_i).select { |day| day.between?(0, 6) }.uniq.sort
    self.recurring = recurrence_frequency != "none"

    if recurring?
      if recurrence_frequency == "weekly" && recurrence_days.blank? && start_time.present?
        self.recurrence_days = [start_time.in_time_zone.wday]
      end
      self.recurrence_days = [] unless recurrence_frequency == "weekly"
    else
      self.recurrence_frequency = "none"
      self.recurrence_days = []
      self.recurrence_ends_on = nil
      self.recurrence_generated_until = nil
    end
  end

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    errors.add(:end_time, "must be after the start time") unless end_time > start_time
  end

  def client_belongs_to_user
    return if client.blank? || user.blank?

    errors.add(:client, "must belong to your account") unless client.user_id == user_id
  end

  def parent_session_belongs_to_user
    return if parent_session.blank? || user.blank?

    errors.add(:parent_session, "must belong to your account") unless parent_session.user_id == user_id
  end

  def recurrence_ends_after_start
    return if recurrence_ends_on.blank? || start_time.blank?

    errors.add(:recurrence_ends_on, "must be after the first session") if recurrence_ends_on < start_time.to_date
  end
end
