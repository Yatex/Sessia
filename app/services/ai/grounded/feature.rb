module Ai
  module Grounded
    module Feature
      module_function

      def inbound_enabled?
        inbound_v2_enabled? || ActiveModel::Type::Boolean.new.cast(ENV["SESSIA_AI_GROUNDED_INBOUND_ENABLED"])
      end

      def inbound_v2_enabled? = enabled?("SESSIA_GROUNDED_INBOUND_V2")
      def before_session_v2_enabled? = enabled?("SESSIA_GROUNDED_BEFORE_SESSION_V2")
      def v2_for?(task)
        (task.trigger_event == "client_replied" && inbound_v2_enabled?) ||
          (task.trigger_event == "before_session" && task.automation_key == "confirm_session" && before_session_v2_enabled?)
      end

      def enabled?(name)
        ActiveModel::Type::Boolean.new.cast(ENV[name])
      end
    end
  end
end
