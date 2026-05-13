module Availability
  class Calendar
    Slot = Struct.new(:starts_at, :ends_at, keyword_init: true) do
      def label
        "#{starts_at.strftime("%a %b %-d, %H:%M")} - #{ends_at.strftime("%H:%M")}"
      end

      def value
        starts_at.strftime("%Y-%m-%dT%H:%M")
      end
    end

    DEFAULT_DURATION_MINUTES = 60
    DEFAULT_STEP_MINUTES = 30

    def initialize(user)
      @user = user
      Availability::Defaults.ensure_for(user)
    end

    def available?(starts_at, duration_minutes: DEFAULT_DURATION_MINUTES, exclude_session: nil)
      start_time = starts_at.in_time_zone(user.time_zone)
      end_time = start_time + duration_minutes.to_i.minutes

      inside_working_hours?(start_time, end_time) &&
        !blocked?(start_time, end_time) &&
        !occupied?(start_time, end_time, exclude_session: exclude_session)
    end

    def blocked?(starts_at, ends_at)
      user.schedule_blocks.active.where("starts_at < ? AND ends_at > ?", ends_at, starts_at).exists?
    end

    def slots_for_day(day, duration_minutes: DEFAULT_DURATION_MINUTES, step_minutes: DEFAULT_STEP_MINUTES, exclude_session: nil)
      local_day = day.to_date
      rules_for(local_day.wday).flat_map do |rule|
        slot_minutes_for(rule, duration_minutes: duration_minutes, step_minutes: step_minutes).filter_map do |minutes|
          start_time = zone.local(local_day.year, local_day.month, local_day.day, minutes / 60, minutes % 60)
          next unless available?(start_time, duration_minutes: duration_minutes, exclude_session: exclude_session)

          Slot.new(starts_at: start_time, ends_at: start_time + duration_minutes.to_i.minutes)
        end
      end
    end

    def slot_availability_for(days, slot_minutes: DEFAULT_STEP_MINUTES, duration_minutes: DEFAULT_DURATION_MINUTES, exclude_session: nil)
      days.each_with_object({}) do |day, lookup|
        slots_for_day(day, duration_minutes: duration_minutes, step_minutes: slot_minutes, exclude_session: exclude_session).each do |slot|
          lookup[[slot.starts_at.to_date, minutes_into_day(slot.starts_at)]] = slot
        end
      end
    end

    def free_slots(from: Time.current, days: 14, duration_minutes: DEFAULT_DURATION_MINUTES, limit: 8, exclude_session: nil)
      start_time = from.in_time_zone(user.time_zone)
      (start_time.to_date...(start_time.to_date + days.to_i)).flat_map do |day|
        slots_for_day(day, duration_minutes: duration_minutes, exclude_session: exclude_session)
      end.select { |slot| slot.starts_at >= start_time }
        .first(limit)
    end

    def free_slot_count_for_day(day, duration_minutes: DEFAULT_DURATION_MINUTES)
      slots_for_day(day, duration_minutes: duration_minutes).size
    end

    def working_slot_minutes_for(days, slot_minutes: DEFAULT_STEP_MINUTES)
      minutes = days.flat_map do |day|
        rules_for(day.to_date.wday).flat_map do |rule|
          (rule.start_minute...rule.end_minute).step(slot_minutes).to_a
        end
      end

      minutes.uniq.sort
    end

    private

    attr_reader :user

    def inside_working_hours?(starts_at, ends_at)
      rules_for(starts_at.wday).any? { |rule| rule.covers?(starts_at, ends_at) }
    end

    def occupied?(starts_at, ends_at, exclude_session:)
      scope = user.sessions.where.not(status: [Session.statuses.fetch("cancelled"), Session.statuses.fetch("no_show")])
        .where("start_time < ? AND end_time > ?", ends_at, starts_at)
      scope = scope.where.not(id: exclude_session.id) if exclude_session&.persisted?
      scope.exists?
    end

    def rules_for(weekday)
      rules_by_weekday[weekday] || []
    end

    def rules_by_weekday
      @rules_by_weekday ||= user.availability_rules.enabled.ordered.to_a.group_by(&:weekday)
    end

    def slot_minutes_for(rule, duration_minutes:, step_minutes:)
      latest_start = rule.end_minute - duration_minutes.to_i
      return [] if latest_start < rule.start_minute

      (rule.start_minute..latest_start).step(step_minutes.to_i).to_a
    end

    def minutes_into_day(time)
      local = time.in_time_zone(user.time_zone)
      local.hour * 60 + local.min
    end

    def zone
      @zone ||= ActiveSupport::TimeZone[user.time_zone] || Time.zone
    end
  end
end
