module Availability
  class Defaults
    DEFAULT_RULES = {
      1 => [[8 * 60, 18 * 60]],
      2 => [[8 * 60, 18 * 60]],
      3 => [[8 * 60, 18 * 60]],
      4 => [[8 * 60, 18 * 60]],
      5 => [[8 * 60, 18 * 60]]
    }.freeze

    def self.ensure_for(user)
      return if user.blank? || user.availability_rules.exists?

      DEFAULT_RULES.each do |weekday, ranges|
        ranges.each do |start_minute, end_minute|
          user.availability_rules.create!(
            weekday: weekday,
            start_minute: start_minute,
            end_minute: end_minute,
            enabled: true
          )
        end
      end
    end
  end
end
