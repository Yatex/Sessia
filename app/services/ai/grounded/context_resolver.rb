module Ai
  module Grounded
    class ContextResolver
      PURPOSE = "sessia-ai-decision-context"

      def initialize(task:)
        @task = task
      end

      def call
        raise ArgumentError, "Grounded context currently supports client replies only." unless task.trigger_event == "client_replied"

        message = task.user.messages.inbound.find(task.context_data.fetch("message_id"))
        client = task.user.clients.find(task.client_id || message.client_id)
        raise ActiveRecord::RecordNotFound, "Inbound message does not belong to the resolved client." unless message.client_id == client.id

        session = resolve_session(client, message)
        setting = task.user.ai_setting || task.user.create_ai_setting!
        payload = token_payload(client: client, session: session, message: message)

        DecisionContext.new(
          task: task,
          workspace: task.user.studio_owner || task.user,
          professional: task.user,
          client: client,
          session: session,
          message: message,
          trigger: "incoming_message",
          ai_setting: setting,
          permissions: permissions_for(setting),
          locale: task.user.locale,
          time_zone: task.user.time_zone,
          context_token: verifier.generate(payload, expires_in: 15.minutes, purpose: PURPOSE)
        )
      end

      def self.verify!(token)
        Rails.application.message_verifier(:sessia_ai_context).verify(token, purpose: PURPOSE).deep_stringify_keys
      end

      private

      attr_reader :task

      def resolve_session(client, message)
        session_id = task.session_id || message.session_id
        return if session_id.blank?

        task.user.sessions.where(client: client).find(session_id)
      end

      def token_payload(client:, session:, message:)
        {
          "version" => 1,
          "task_id" => task.id,
          "workspace_id" => (task.user.studio_id || task.user_id),
          "professional_id" => task.user_id,
          "client_id" => client.id,
          "session_id" => session&.id,
          "message_id" => message.id,
          "trigger" => "incoming_message"
        }.compact
      end

      def permissions_for(setting)
        {
          "answer_basic_questions" => setting.answer_basic_questions?,
          "confirm_sessions" => setting.confirm_sessions?,
          "reschedule_sessions" => setting.answer_basic_questions?,
          "create_alerts" => setting.escalate_important_conversations?,
          "read_payments" => true,
          "write_payments" => false
        }
      end

      def verifier
        Rails.application.message_verifier(:sessia_ai_context)
      end
    end
  end
end
