module Ai
  module Grounded
    module Feature
      module_function

      def grounded_for?(task)
        task.trigger_event == "client_replied" ||
          (task.trigger_event == "before_session" && task.automation_key == "confirm_session")
      end

      def v2_for?(task) = grounded_for?(task)
    end
  end
end
