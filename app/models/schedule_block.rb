class ScheduleBlock < ApplicationRecord
  STATUSES = %w[active cancelled].freeze

  belongs_to :user

  validates :title, presence: true, length: { maximum: 140 }
  validates :starts_at, :ends_at, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_after_start

  scope :active, -> { where(status: "active") }
  scope :upcoming, -> { where("ends_at >= ?", Time.current) }
  scope :chronological, -> { order(:starts_at, :ends_at) }

  def active?
    status == "active"
  end

  def cancel!
    update!(status: "cancelled")
  end

  private

  def end_after_start
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") unless ends_at > starts_at
  end
end
