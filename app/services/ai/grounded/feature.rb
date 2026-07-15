module Ai
  module Grounded
    module Feature
      module_function

      def inbound_enabled?
        ActiveModel::Type::Boolean.new.cast(ENV["SESSIA_AI_GROUNDED_INBOUND_ENABLED"])
      end
    end
  end
end
