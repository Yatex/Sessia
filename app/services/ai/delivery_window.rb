module Ai
  class DeliveryWindow
    DEFAULT_START_HOUR = 7
    DEFAULT_END_HOUR = 22
    URGENT_SESSION_WINDOW = 3.hours

    class << self
      def allows?(task:, reference_time: Time.current)
        return true if task.blank?
        return true unless proactive_task?(task)
        return true if within_delivery_hours?(task.user, reference_time)
        return true if urgent_session_exception?(task, reference_time)

        false
      end

      private

      def proactive_task?(task)
        task.trigger_event != "client_replied"
      end

      def within_delivery_hours?(user, reference_time)
        local_time = reference_time.in_time_zone(time_zone_for(user))
        local_time.hour >= DEFAULT_START_HOUR && local_time.hour < DEFAULT_END_HOUR
      end

      def urgent_session_exception?(task, reference_time)
        session = task.session
        return false if session.blank?
        return false unless task.trigger_event.in?(%w[before_session no_response_window_reached schedule_blocked])

        session.start_time <= reference_time + URGENT_SESSION_WINDOW
      end

      def time_zone_for(user)
        ActiveSupport::TimeZone[user&.time_zone] || Time.zone
      end
    end
  end
end
