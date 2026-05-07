class RecurringSessionGenerator
  DEFAULT_MONTHS_AHEAD = 3

  def initialize(session)
    @session = session
  end

  def generate!
    return 0 unless session.recurring_series?

    occurrence_dates.count do |date|
      create_or_update_occurrence(date)
    end.tap do
      session.update_column(:recurrence_generated_until, generation_end_date) if session.persisted?
    end
  end

  private

  attr_reader :session

  def occurrence_dates
    case session.recurrence_frequency
    when "weekly" then weekly_dates
    when "monthly" then monthly_dates
    else []
    end
  end

  def weekly_dates
    start_date = session.start_time.to_date + 1.day
    (start_date..generation_end_date).select { |date| session.recurrence_days.include?(date.wday) }
  end

  def monthly_dates
    dates = []
    date = session.start_time.to_date.next_month
    while date <= generation_end_date
      dates << date
      date = date.next_month
    end
    dates
  end

  def create_or_update_occurrence(date)
    starts_at = occurrence_time(date, session.start_time)
    occurrence = session.user.sessions.find_or_initialize_by(parent_session: session, start_time: starts_at)
    occurrence.assign_attributes(
      client: session.client,
      title: session.title,
      end_time: starts_at + session.duration_minutes.minutes,
      status: "scheduled",
      confirmation_status: session.confirmation_status,
      payment_status: session.payment_status,
      price_cents: session.price_cents,
      currency: session.currency,
      sync_to_google_calendar: session.sync_to_google_calendar,
      recurring: false,
      recurrence_frequency: "none",
      recurrence_days: [],
      recurrence_rule: "Generated from #{session.title}",
      notes: session.notes
    )
    occurrence.save!
  end

  def occurrence_time(date, source_time)
    Time.use_zone(session.user.time_zone) do
      Time.zone.local(date.year, date.month, date.day, source_time.in_time_zone.hour, source_time.in_time_zone.min)
    end
  end

  def generation_end_date
    session.recurrence_ends_on.presence || DEFAULT_MONTHS_AHEAD.months.from_now.to_date
  end
end
