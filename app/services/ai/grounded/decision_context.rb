module Ai
  module Grounded
    DecisionContext = Data.define(
      :task,
      :workspace,
      :professional,
      :client,
      :session,
      :message,
      :trigger,
      :ai_setting,
      :permissions,
      :locale,
      :time_zone,
      :context_token
    )
  end
end
