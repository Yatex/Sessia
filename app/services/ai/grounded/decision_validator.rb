module Ai
  module Grounded
    class DecisionValidator
      ALLOWED_ACTIONS = %w[send_message clarify propose_reschedule propose_session_status_change create_professional_task create_alert no_action].freeze
      SESSION_EFFECTS = %w[confirm_session mark_session_maybe decline_session reschedule_session].freeze

      Result = Data.define(:valid, :decision, :errors) do
        def valid?
          valid
        end
      end

      def initialize(context:, tools:, instruction:)
        @context = context
        @tools = tools
        @instruction = instruction
      end

      def call(decision)
        errors = []
        validate_context(errors)
        validate_schema(decision, errors)
        validate_evidence(decision, errors)
        validate_effect(decision, errors)
        validate_confidence(decision, errors)
        Result.new(valid: errors.empty?, decision: decision, errors: errors)
      rescue StandardError => error
        Result.new(valid: false, decision: decision, errors: ["validator_error: #{error.message}"])
      end

      private

      attr_reader :context, :tools, :instruction

      def validate_context(errors)
        token = ContextResolver.verify!(context.context_token)
        expected = {
          "task_id" => context.task.id,
          "professional_id" => context.professional.id,
          "client_id" => context.client.id,
          "message_id" => context.message.id,
          "session_id" => context.session&.id
        }.compact.transform_values(&:to_s)
        actual = token.slice(*expected.keys).transform_values(&:to_s)
        errors << "signed_context_mismatch" unless actual == expected
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        errors << "invalid_context_signature"
      end

      def validate_schema(decision, errors)
        errors << "unsupported_action" unless ALLOWED_ACTIONS.include?(decision["action"])
        errors << "missing_reasoning_summary" if decision["reasoning_summary"].blank?
        errors << "message_body_required" if decision.dig("message", "send") && decision.dig("message", "body").blank?
        errors << "message_too_long" if decision.dig("message", "body").to_s.length > 2_000
      end

      def validate_evidence(decision, errors)
        ids = Array(decision["evidence_ids"])
        errors << "evidence_required" if evidence_required?(decision) && ids.empty?
        unknown = ids.reject { |id| tools.evidence.include?(id) }
        errors << "unknown_evidence:#{unknown.join(',')}" if unknown.any?
        errors << "irrelevant_evidence" unless relevant_evidence?(decision, ids)
      end

      def evidence_required?(decision)
        decision["action"] != "no_action"
      end

      def relevant_evidence?(decision, ids)
        return true if decision["action"] == "no_action"
        return false if ids.empty?

        types = ids.filter_map { |id| tools.evidence.include?(id) ? tools.evidence.fetch(id)["source_type"] : nil }
        case decision["action"]
        when "propose_session_status_change"
          types.include?("message") && types.include?("session")
        when "propose_reschedule"
          types.include?("message") && types.include?("availability")
        when "send_message", "clarify"
          types.include?("message") || types.include?("session") || types.include?("charge")
        else
          types.include?("message")
        end
      end

      def validate_effect(decision, errors)
        effect = decision.fetch("effect", {})
        type = effect["type"]
        return if type == "no_effect"

        if SESSION_EFFECTS.include?(type)
          errors << "session_required" if context.session.blank?
          errors << "unauthorized_session" unless effect["session_id"].to_s == context.session&.id.to_s
        end

        case type
        when "confirm_session", "mark_session_maybe", "decline_session"
          errors << "confirmation_automation_disabled" unless context.permissions["confirm_sessions"]
          errors << "session_not_confirmable" unless context.session&.scheduled?
          errors << "ambiguous_confirmation_context" unless unambiguous_confirmation_context?
        when "reschedule_session"
          errors << "rescheduling_disabled" unless context.permissions["reschedule_sessions"]
          errors << "target_slot_not_grounded" unless grounded_target_slot?(effect["target_start_at"], decision["evidence_ids"])
        end

        errors << "payment_mutation_forbidden" if type.to_s.match?(/payment|charge|credit|refund|waive|forgive/i)
      end

      def validate_confidence(decision, errors)
        minimum = decision["action"].start_with?("propose_") ? 0.9 : 0.6
        errors << "confidence_below_threshold" if decision["confidence"].to_f < minimum
      end

      def unambiguous_confirmation_context?
        return false if context.session.blank?
        return false unless context.message.session_id == context.session.id

        recent_confirmation_requests = context.professional.messages.outbound
          .where(client: context.client, session: context.session)
          .where("created_at >= ?", 14.days.ago)
          .where("metadata ->> 'automation_key' = ?", "confirm_session")
        recent_confirmation_requests.exists?
      end

      def grounded_target_slot?(target, evidence_ids)
        return false if target.blank?

        Array(evidence_ids).any? do |id|
          next false unless tools.evidence.include?(id)
          item = tools.evidence.fetch(id)
          item["source_type"] == "availability" && item.dig("value", "starts_at") == target
        end
      end
    end
  end
end
