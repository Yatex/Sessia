module Ai
  module Grounded
    class ToolRunner
      ALLOWED_TOOLS = %w[client_context session_context conversation_history pending_interaction professional_settings].freeze

      def initialize(context_token:, tool_name:)
        @scope = ContextResolver.verify!(context_token)
        @tool_name = tool_name.to_s
      end

      def call
        raise ArgumentError, "Tool is not allowed." unless ALLOWED_TOOLS.include?(tool_name)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result, evidence = send(tool_name)
        {
          tool: tool_name,
          result: result,
          evidence: evidence,
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        }
      end

      private

      attr_reader :scope, :tool_name

      def professional = @professional ||= User.find(scope.fetch("professional_id"))
      def client = @client ||= professional.clients.find(scope.fetch("client_id"))
      def session_record = @session_record ||= scope["session_id"].present? ? professional.sessions.where(client: client).find(scope["session_id"]) : nil
      def current_message = @current_message ||= scope["message_id"].present? ? professional.messages.inbound.where(client: client).find(scope["message_id"]) : nil

      def item(source, field, value, metadata = {})
        { evidence_id: "#{source.class.model_name.singular}.#{source.id}.#{field}", source_type: source.class.model_name.singular, source_id: source.id.to_s, field: field.to_s, value: serialize(value), metadata: metadata }
      end

      def client_context
        evidence = [item(client, :name, client.name), item(client, :status, client.status)]
        [{ name: client.name, status: client.status }, evidence]
      end

      def session_context
        return [{ present: false }, []] if session_record.blank?
        evidence = %i[title start_time end_time status confirmation_status].map { |field| item(session_record, field, session_record.public_send(field)) }
        [{ present: true, title: session_record.title, starts_at: session_record.start_time.iso8601, ends_at: session_record.end_time.iso8601, status: session_record.status, confirmation_status: session_record.confirmation_status }, evidence]
      end

      def conversation_history
        messages = professional.messages.where(client: client).order(created_at: :desc).limit(12).reverse
        evidence = messages.map { |message| item(message, :body, message.body, direction: message.direction, occurred_at: message.created_at.iso8601) }
        [{ messages: messages.map { |message| { direction: message.direction, body: message.body, occurred_at: message.created_at.iso8601, evidence_id: "message.#{message.id}.body" } } }, evidence]
      end

      def pending_interaction
        request = professional.messages.outbound.where(client: client, session: session_record).where("metadata ->> 'automation_key' = ?", "confirm_session").order(created_at: :desc).first
        evidence = current_message ? [item(current_message, :body, current_message.body)] : []
        if request
          evidence << item(request, :pending_confirmation, true, session_id: session_record&.id)
        end
        pending_count = professional.messages.outbound.where(client: client).where("metadata ->> 'automation_key' = ?", "confirm_session").where("created_at >= ?", 14.days.ago).distinct.count(:session_id)
        [{ type: request ? "session_confirmation" : nil, pending: request.present?, pending_count: pending_count, session_id: request&.session_id }, evidence]
      end

      def professional_settings
        setting = professional.ai_setting || professional.create_ai_setting!
        evidence = [item(setting, :instructions, setting.instructions), item(setting, :confirm_sessions, setting.confirm_sessions?)]
        [{ instructions: setting.instructions, confirm_sessions: setting.confirm_sessions?, locale: professional.locale, time_zone: professional.time_zone }, evidence]
      end

      def serialize(value)
        case value
        when Time, ActiveSupport::TimeWithZone then value.iso8601
        when Date then value.iso8601
        else value
        end
      end
    end
  end
end
