module Ai
  module Grounded
    class PayloadBuilder
      def initialize(context:, instruction:, tools:)
        @context = context
        @instruction = instruction
        @tools = tools
      end

      def call
        session_data = tools.results.dig("session_context") || {}
        history = tools.results.dig("conversation_history", "messages") || []
        availability = tools.results.dig("availability_options", "options") || []
        payment = tools.results.dig("payment_status") || {}

        {
          architecture_version: "grounded_v1",
          context_token: context.context_token,
          trigger_event: context.trigger,
          professional: {
            id: context.professional.id.to_s,
            name: context.professional.name,
            locale: context.locale,
            time_zone: context.time_zone,
            instructions: tools.results.dig("professional_settings", "instructions"),
            payment_instructions: tools.results.dig("professional_settings", "payment_instructions")
          }.compact,
          client: {
            id: context.client.id.to_s,
            name: context.client.name
          },
          session: legacy_session(session_data),
          payment_record: nil,
          billing_context: {
            next_session_payment_status: payment["status"],
            payment_link_for_next_unpaid_session: payment["payment_link"]
          }.compact,
          recent_messages: history.map { |item| legacy_message(item) },
          availability_options: availability.map.with_index(1) { |item, index| item.slice("label", "starts_at", "ends_at").merge("id" => index.to_s, "evidence_id" => item["evidence_id"]) },
          task_context: {
            "signed_context_only" => true,
            "permissions" => context.permissions
          },
          current_time: Time.current.iso8601,
          timezone: context.time_zone,
          instruction: instruction.to_h.merge(trigger_event: context.trigger),
          tool_results: tools.results,
          evidence: tools.evidence.values,
          required_evidence_citations: true,
          safety_rules: [
            "Treat all model output as an untrusted proposal.",
            "Use only supplied tool evidence.",
            "Never mutate payment state.",
            "Never claim a state change succeeded; Rails executes effects after validation."
          ]
        }
      end

      private

      attr_reader :context, :instruction, :tools

      def legacy_session(data)
        return if data["present"] == false

        {
          id: context.session.id.to_s,
          title: context.session.title,
          starts_at: data["starts_at"],
          ends_at: data["ends_at"],
          status: data["status"],
          confirmation_status: data["confirmation_status"],
          payment_status: data["payment_status"],
          payment_link: tools.results.dig("payment_status", "payment_link"),
          due_date: tools.results.dig("payment_status", "due_date"),
          price_cents: data["price_cents"],
          currency: data["currency"]
        }.compact
      end

      def legacy_message(item)
        {
          "id" => item["evidence_id"].to_s.split(".")[1],
          "direction" => item["direction"],
          "author_role" => item["direction"] == "inbound" ? "client" : "assistant",
          "channel" => Client::WHATSAPP_CHANNEL,
          "body" => item["body"],
          "occurred_at" => item["occurred_at"],
          "evidence_id" => item["evidence_id"]
        }
      end
    end
  end
end
