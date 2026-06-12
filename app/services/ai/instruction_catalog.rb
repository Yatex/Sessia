module Ai
  class InstructionCatalog
    Instruction = Struct.new(:key, :name, :description, :trigger_event, :allowed_actions, keyword_init: true) do
      def to_h
        {
          key: key,
          name: name,
          description: description,
          trigger_event: trigger_event,
          allowed_actions: allowed_actions
        }
      end

      def allows_action?(action_name)
        allowed_actions.include?(action_name.to_s)
      end
    end

    AUTOMATION_INSTRUCTIONS = {
      "confirm_session" => Instruction.new(
        key: "confirm_session",
        name: "Confirm upcoming session",
        trigger_event: "before_session",
        description: "Ask the client to confirm an upcoming scheduled session. Keep it short and appropriate for WhatsApp.",
        allowed_actions: %w[send_message schedule_follow_up do_nothing]
      ),
      "send_pre_session_reminder" => Instruction.new(
        key: "send_pre_session_reminder",
        name: "Send pre-session reminder",
        trigger_event: "before_session",
        description: "Remind a confirmed client about an upcoming session without changing any status.",
        allowed_actions: %w[send_message do_nothing]
      ),
      "follow_up_no_response" => Instruction.new(
        key: "follow_up_no_response",
        name: "Follow up when there is no response",
        trigger_event: "no_response_window_reached",
        description: "Send one concise follow-up when a confirmation request has not received a client response.",
        allowed_actions: %w[send_message schedule_follow_up do_nothing]
      ),
      "ask_feedback_after_session" => Instruction.new(
        key: "ask_feedback_after_session",
        name: "Ask for feedback after session",
        trigger_event: "after_session",
        description: "Ask the client how the completed session felt and capture lightweight feedback.",
        allowed_actions: %w[send_message do_nothing]
      ),
      "payment_reminder" => Instruction.new(
        key: "payment_reminder",
        name: "Send payment reminder",
        trigger_event: "payment_due",
        description: "Remind the client about a pending session payment. Use read-only billing context or professional.payment_instructions. Do not mark payments paid or invent payment methods.",
        allowed_actions: %w[send_message schedule_follow_up do_nothing]
      ),
      "blocked_time_rebooking" => Instruction.new(
        key: "blocked_time_rebooking",
        name: "Rebook blocked session",
        trigger_event: "schedule_blocked",
        description: "Tell the client the professional is no longer available at the previous time and offer available replacement slots.",
        allowed_actions: %w[send_message do_nothing]
      )
    }.freeze

    SETTING_FOR_INSTRUCTION = {
      "confirm_session" => :confirm_sessions,
      "send_pre_session_reminder" => :send_pre_session_reminders,
      "follow_up_no_response" => :follow_up_no_response,
      "ask_feedback_after_session" => :ask_feedback_after_sessions,
      "payment_reminder" => :payment_reminders
    }.freeze

    def self.for_task(task, ai_setting:)
      if task.trigger_event == "client_replied"
        return client_reply_instruction(ai_setting)
      end

      instruction = AUTOMATION_INSTRUCTIONS[task.automation_key.to_s]
      return if instruction.blank?
      return instruction if instruction.key == "blocked_time_rebooking"

      enabled_setting = SETTING_FOR_INSTRUCTION.fetch(instruction.key)
      return unless ai_setting.public_send("#{enabled_setting}?")

      instruction
    end

    def self.client_reply_instruction(ai_setting)
      allowed_actions = %w[create_client_note do_nothing]
      allowed_actions << "send_message" if ai_setting.answer_basic_questions?
      allowed_actions << "alert_professional" if ai_setting.escalate_important_conversations?
      allowed_actions.concat(%w[mark_session_confirmed mark_session_maybe mark_session_declined]) if ai_setting.confirm_sessions?
      allowed_actions << "reschedule_session" if ai_setting.answer_basic_questions?
      allowed_actions << "schedule_follow_up" if ai_setting.follow_up_no_response?
      allowed_actions.uniq!

      return if allowed_actions == %w[create_client_note do_nothing]

      Instruction.new(
        key: "answer_client_reply",
        name: "Answer client reply",
        trigger_event: "client_replied",
        description: "Classify and answer the latest client WhatsApp-style reply using only Sessia context. Offer available schedule options when the client asks to move a session, reschedule when they choose one, answer payment questions from read-only billing context or professional.payment_instructions, and escalate sensitive topics or uncertainty. Never update payment records.",
        allowed_actions: allowed_actions
      )
    end
  end
end
