module Ai
  module Grounded
    class ToolRunner
      AVAILABILITY_DAYS = 14
      AVAILABILITY_LIMIT = 6
      ALLOWED_TOOLS = %w[
        client_context
        session_context
        conversation_history
        pending_interaction
        professional_settings
        availability_options
        payment_status
        workspace_policies
      ].freeze

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

      def virtual_item(id:, source_type:, field:, value:, metadata: {})
        {
          evidence_id: id,
          source_type: source_type,
          source_id: nil,
          field: field.to_s,
          value: serialize(value),
          metadata: metadata
        }
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

      def availability_options
        return [{ options: [] }, []] if session_record.blank?

        duration = session_record.duration_minutes.positive? ? session_record.duration_minutes : 50
        slots = Availability::FreeSlotFinder.new(professional).call(
          from: Time.current,
          days: AVAILABILITY_DAYS,
          duration_minutes: duration,
          limit: AVAILABILITY_LIMIT,
          exclude_session: session_record
        )
        evidence = slots.map do |slot|
          virtual_item(
            id: "availability.#{professional.id}.#{slot.starts_at.to_i}.#{duration}",
            source_type: "availability",
            field: :available_slot,
            value: { starts_at: slot.starts_at.iso8601, ends_at: slot.ends_at.iso8601 },
            metadata: { professional_id: professional.id, duration_minutes: duration }
          )
        end
        options = slots.zip(evidence).map do |slot, item|
          {
            evidence_id: item.fetch(:evidence_id),
            starts_at: slot.starts_at.iso8601,
            ends_at: slot.ends_at.iso8601,
            label: slot.label
          }
        end
        [{ options: options }, evidence]
      end

      def payment_status
        return [{ tracked: false }, []] if session_record.blank?

        charge = session_record.main_charge
        evidence = [item(session_record, :payment_status, session_record.payment_status)]
        if charge.present?
          %i[status amount_cents currency due_date payment_url].each do |field|
            evidence << item(charge, field, charge.public_send(field))
          end
        end
        [{
          tracked: charge.present? || !session_record.payment_not_tracked?,
          status: session_record.payment_status,
          amount_cents: charge&.amount_cents || session_record.price_cents,
          currency: charge&.currency || session_record.currency,
          due_date: charge&.due_date&.iso8601,
          payment_required_before_session: session_record.payment_required_before_session?,
          payment_link: charge&.payment_url.presence
        }.compact, evidence]
      end

      def workspace_policies
        [{
          workspace_type: (professional.studio_owner || professional).account_type,
          professional_scope_id: professional.id.to_s,
          payments_read_only: true,
          recurring_changes_apply_to_occurrence_only: true
        }, []]
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
