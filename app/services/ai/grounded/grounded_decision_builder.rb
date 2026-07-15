module Ai
  module Grounded
    class GroundedDecisionBuilder
      ACTION_MAP = {
        "send_message" => ["send_message", nil],
        "mark_session_confirmed" => ["propose_session_status_change", "confirm_session"],
        "mark_session_maybe" => ["propose_session_status_change", "mark_session_maybe"],
        "mark_session_declined" => ["propose_session_status_change", "decline_session"],
        "reschedule_session" => ["propose_reschedule", "reschedule_session"],
        "create_client_note" => ["create_professional_task", "create_client_note"],
        "alert_professional" => ["create_alert", "create_alert"],
        "schedule_follow_up" => ["create_professional_task", "schedule_follow_up"],
        "do_nothing" => ["no_action", nil]
      }.freeze

      def initialize(context:, tools:)
        @context = context
        @tools = tools
      end

      def call(candidate)
        candidate = candidate.to_h.deep_stringify_keys
        action, effect_type = ACTION_MAP.fetch(candidate.fetch("action"))
        {
          "action" => action,
          "message" => {
            "send" => candidate["message_body"].present?,
            "body" => candidate["message_body"]
          },
          "effect" => effect_for(effect_type, candidate),
          "confidence" => normalize_confidence(candidate["confidence"]),
          "evidence_ids" => Array(candidate["evidence_ids"]).map(&:to_s).uniq,
          "reasoning_summary" => candidate["reasoning_summary"].to_s,
          "human_review_required" => candidate["human_review_required"] == true,
          "legacy_decision" => candidate
        }
      end

      private

      attr_reader :context, :tools

      def effect_for(type, candidate)
        return { "type" => "no_effect" } if type.blank?

        {
          "type" => type,
          "session_id" => candidate["session_id"].presence || context.session&.id&.to_s,
          "target_start_at" => candidate["target_start_at"],
          "note_body" => candidate["note_body"],
          "alert_body" => candidate["alert_body"],
          "follow_up_at" => candidate["follow_up_at"]
        }.compact
      end

      def normalize_confidence(value)
        number = value.to_f
        number > 1 ? number / 100.0 : number
      end
    end
  end
end
