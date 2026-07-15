module Ai
  module Grounded
    class Toolset
      HISTORY_LIMIT = 12
      AVAILABILITY_DAYS = 14
      AVAILABILITY_LIMIT = 6

      Result = Data.define(:results, :evidence, :executed_tools)

      def initialize(context:)
        @context = context
        @evidence = EvidenceSet.new
      end

      def call
        results = {
          "client_context" => client_context,
          "session_context" => session_context,
          "conversation_history" => conversation_history,
          "professional_settings" => professional_settings,
          "availability_options" => availability_options,
          "payment_status" => payment_status,
          "workspace_policies" => workspace_policies
        }
        Result.new(results: results, evidence: evidence, executed_tools: results.keys)
      end

      private

      attr_reader :context, :evidence

      def client_context
        client = context.client
        {
          "name" => client.name,
          "professional_name" => context.professional.name,
          "language" => context.locale,
          "time_zone" => context.time_zone,
          "evidence_ids" => [evidence.add(source: client, field: :name, value: client.name)]
        }
      end

      def session_context
        session = context.session
        return { "present" => false, "evidence_ids" => [] } if session.blank?

        fields = %i[start_time end_time status confirmation_status payment_status price_cents currency payment_required_before_session recurring parent_session_id]
        evidence_ids = fields.filter_map { |field| evidence.add(source: session, field: field, value: session.public_send(field)) }
        {
          "present" => true,
          "title" => session.title,
          "starts_at" => session.start_time.iso8601,
          "ends_at" => session.end_time.iso8601,
          "status" => session.status,
          "confirmation_status" => session.confirmation_status,
          "payment_status" => session.payment_status,
          "price_cents" => session.price_cents,
          "currency" => session.currency,
          "payment_required_before_session" => session.payment_required_before_session?,
          "recurring_occurrence" => session.generated_occurrence?,
          "evidence_ids" => evidence_ids
        }
      end

      def conversation_history
        messages = context.professional.messages.where(client: context.client).recent_first.limit(HISTORY_LIMIT).to_a.reverse
        {
          "messages" => messages.map do |message|
            evidence_id = evidence.add(
              source: message,
              field: :body,
              value: message.body.to_s,
              metadata: { direction: message.direction, occurred_at: message.sent_at || message.created_at, session_id: message.session_id }
            )
            {
              "evidence_id" => evidence_id,
              "direction" => message.direction,
              "body" => message.body.to_s,
              "occurred_at" => (message.sent_at || message.created_at).iso8601,
              "session_context" => message.session_id == context.session&.id
            }
          end,
          "evidence_ids" => messages.map { |message| "message.#{message.id}.body" }
        }
      end

      def professional_settings
        setting = context.ai_setting
        {
          "instructions" => setting.instructions.presence,
          "features" => AiSetting::FEATURE_FIELDS.index_with { |field| setting.public_send("#{field}?") },
          "payment_instructions" => context.professional.payment_instructions.presence,
          "evidence_ids" => [
            evidence.add(source: setting, field: :instructions, value: setting.instructions.to_s),
            evidence.add(source: context.professional, field: :payment_instructions, value: context.professional.payment_instructions.to_s)
          ].compact
        }
      end

      def availability_options
        session = context.session
        return { "options" => [], "evidence_ids" => [] } if session.blank?

        duration = session.duration_minutes.positive? ? session.duration_minutes : 50
        slots = Availability::FreeSlotFinder.new(context.professional).call(
          from: Time.current,
          days: AVAILABILITY_DAYS,
          duration_minutes: duration,
          limit: AVAILABILITY_LIMIT,
          exclude_session: session
        )
        options = slots.map do |slot|
          id = "availability.#{context.professional.id}.#{slot.starts_at.to_i}.#{duration}"
          evidence.add_virtual(
            id: id,
            source_type: "availability",
            field: :available_slot,
            value: { starts_at: slot.starts_at.iso8601, ends_at: slot.ends_at.iso8601 },
            metadata: { professional_id: context.professional.id, duration_minutes: duration }
          )
          { "evidence_id" => id, "starts_at" => slot.starts_at.iso8601, "ends_at" => slot.ends_at.iso8601, "label" => slot.label }
        end
        { "options" => options, "evidence_ids" => options.pluck("evidence_id") }
      end

      def payment_status
        session = context.session
        charge = session&.main_charge
        return { "tracked" => false, "evidence_ids" => [] } if session.blank?

        ids = [evidence.add(source: session, field: :payment_status, value: session.payment_status)]
        if charge.present?
          %i[status amount_cents currency due_date payment_url].each do |field|
            ids << evidence.add(source: charge, field: field, value: charge.public_send(field))
          end
        end
        {
          "tracked" => charge.present? || !session.payment_not_tracked?,
          "status" => session.payment_status,
          "amount_cents" => charge&.amount_cents || session.price_cents,
          "currency" => charge&.currency || session.currency,
          "due_date" => charge&.due_date&.iso8601,
          "payment_required_before_session" => session.payment_required_before_session?,
          "payment_link" => charge&.payment_url.presence,
          "evidence_ids" => ids.compact
        }
      end

      def workspace_policies
        {
          "workspace_type" => context.workspace.account_type,
          "professional_scope_id" => context.professional.id.to_s,
          "payments_read_only" => true,
          "recurring_changes_apply_to_occurrence_only" => true,
          "evidence_ids" => []
        }
      end
    end
  end
end
