class AvailabilityRule < ApplicationRecord
  WEEKDAY_LABELS = {
    0 => "Sunday",
    1 => "Monday",
    2 => "Tuesday",
    3 => "Wednesday",
    4 => "Thursday",
    5 => "Friday",
    6 => "Saturday"
  }.freeze

  belongs_to :user

  validates :weekday, inclusion: { in: WEEKDAY_LABELS.keys }
  validates :start_minute, :end_minute, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 24 * 60 }
  validate :end_after_start

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:weekday, :start_minute) }

  def self.minutes_from_time(value)
    parts = value.to_s.split(":").map(&:to_i)
    return if parts.size < 2

    hour, minute = parts
    return unless hour.between?(0, 23) && minute.between?(0, 59)

    hour * 60 + minute
  end

  def self.time_label(minutes)
    format("%02d:%02d", minutes.to_i / 60, minutes.to_i % 60)
  end

  def weekday_label
    WEEKDAY_LABELS.fetch(weekday)
  end

  def start_label
    self.class.time_label(start_minute)
  end

  def end_label
    self.class.time_label(end_minute)
  end

  def covers?(starts_at, ends_at)
    local_start = starts_at.in_time_zone(user.time_zone)
    local_end = ends_at.in_time_zone(user.time_zone)
    return false unless enabled?
    return false unless local_start.to_date == local_end.to_date
    return false unless local_start.wday == weekday

    start_minutes = local_start.hour * 60 + local_start.min
    end_minutes = local_end.hour * 60 + local_end.min
    start_minutes >= start_minute && end_minutes <= end_minute
  end

  private

  def end_after_start
    return if start_minute.blank? || end_minute.blank?

    errors.add(:end_minute, "must be after the start time") unless end_minute > start_minute
  end
end
