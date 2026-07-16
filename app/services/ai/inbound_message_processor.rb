module Ai
  class InboundMessageProcessor
    def initialize(message:, decision_client: DecisionServiceClient.new)
      @message = message
      @decision_client = decision_client
    end

    def call
      return unless message.inbound?

      setting = message.user.ai_setting || message.user.create_ai_setting!
      instruction = Ai::InstructionCatalog.client_reply_instruction(setting)
      return if instruction.blank?

      idempotency_key = Ai::IdempotencyKey.for_task(
        user: message.user, client: message.client, session: message.session || latest_relevant_session,
        automation_key: "answer_client_reply", trigger_event: "client_replied",
        scheduled_window: "message_#{message.id}", channel: message.channel
      )
      task = message.user.ai_tasks.find_or_create_by!(idempotency_key: idempotency_key) do |new_task|
        new_task.assign_attributes(
        client: message.client,
        session: message.session || latest_relevant_session,
        trigger_event: "client_replied",
        automation_key: "answer_client_reply",
        scheduled_for: Time.current,
        context_data: {
          "message_id" => message.id,
          "subject" => message.subject
        }.compact
        )
      end

      Ai::TaskProcessor.new(task: task, decision_client: decision_client).call if task.status_pending?
    end

    private

    attr_reader :message, :decision_client

    def latest_relevant_session
      message.client&.sessions&.where("end_time >= ?", 7.days.ago)&.chronological&.first
    end
  end
end
