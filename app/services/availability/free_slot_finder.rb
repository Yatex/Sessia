module Availability
  class FreeSlotFinder
    def initialize(user)
      @calendar = Availability::Calendar.new(user)
    end

    def call(from: Time.current, days: 14, duration_minutes: 60, limit: 8, exclude_session: nil)
      calendar.free_slots(
        from: from,
        days: days,
        duration_minutes: duration_minutes,
        limit: limit,
        exclude_session: exclude_session
      )
    end

    private

    attr_reader :calendar
  end
end
