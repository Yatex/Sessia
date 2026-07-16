module Ai
  module Grounded
    class TaskProcessor
      def initialize(task:, decision_client:, dispatcher: Messaging::Dispatcher.new)
        @task = task
        @decision_client = decision_client
        @dispatcher = dispatcher
      end

      def call
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        context = ContextResolver.new(task: task).call
        instruction = Ai::InstructionCatalog.for_task(task, ai_setting: context.ai_setting)
        return skipped_result("No enabled AI instruction matched this task.") if instruction.blank?

        tools = Ai::Grounded::Feature.v2_for?(task) ? nil : Toolset.new(context: context).call
        payload = PayloadBuilder.new(context: context, instruction: instruction, tools: tools).call
        candidate = decision_client.decide(payload)
        decision_metadata = {}
        if Ai::Grounded::Feature.v2_for?(task)
          metadata = candidate.delete("_trace") || candidate.delete(:_trace) || {}
          metadata = independently_resolve_requested_tools(context, metadata)
          decision_metadata = metadata
          tools = ToolSnapshot.new(metadata)
        end
        grounded = GroundedDecisionBuilder.new(context: context, tools: tools).call(candidate)
        validation = DecisionValidator.new(context: context, tools: tools, instruction: instruction).call(grounded)

        unless validation.valid?
          return rejected_result(context: context, tools: tools, candidate: candidate, grounded: grounded, errors: validation.errors, started_at: started_at)
        end

        executor_result = Ai::ActionExecutor.new(task: task, context: legacy_context(context), instruction: instruction, dispatcher: dispatcher).call(grounded.fetch("legacy_decision"))
        {
          "status" => executor_result.status,
          "error_message" => executor_result.error_message,
          "activity_summary" => executor_result.activity_summary,
          "performed_action" => executor_result.performed_action,
          "architecture_version" => "grounded_v1",
          "trigger" => context.trigger,
          "context_scope" => context_scope(context),
          "tools_executed" => tools.executed_tools,
          "tools_requested" => tools.executed_tools,
          "tools_completed" => tools.executed_tools,
          "tool_errors" => tools.respond_to?(:errors) ? tools.errors : [],
          "decision_metadata" => decision_metadata,
          "evidence" => tools.evidence.values,
          "candidate_decision" => candidate,
          "grounded_decision" => grounded,
          "validation" => { "valid" => true, "errors" => [] },
          "effect_execution" => executor_result.to_h,
          "latency_ms" => elapsed_ms(started_at)
        }.compact
      rescue StandardError => error
        {
          "status" => "failed",
          "error_message" => error.message,
          "activity_summary" => "Grounded AI task failed safely.",
          "architecture_version" => "grounded_v1",
          "failure_details" => { "error_class" => error.class.name, "error_message" => error.message },
          "latency_ms" => elapsed_ms(started_at)
        }
      end

      private

      attr_reader :task, :decision_client, :dispatcher

      def independently_resolve_requested_tools(context, metadata)
        metadata = metadata.to_h.deep_stringify_keys
        requested = Array(metadata["tools_requested"]) & ToolRunner::ALLOWED_TOOLS
        results = {}
        evidence = []
        completed = []
        errors = Array(metadata["tool_errors"])
        requested.each do |name|
          response = ToolRunner.new(context_token: context.context_token, tool_name: name).call.deep_stringify_keys
          results[name] = response["result"]
          evidence.concat(Array(response["evidence"]))
          completed << name
        rescue StandardError => error
          errors << { "tool" => name, "error" => error.message }
        end
        metadata.merge("tool_results" => results, "evidence" => evidence, "tools_completed" => completed, "tool_errors" => errors)
      end

      def rejected_result(context:, tools:, candidate:, grounded:, errors:, started_at:)
        {
          "status" => "skipped",
          "activity_summary" => "AI decision rejected by Rails validation.",
          "architecture_version" => "grounded_v1",
          "trigger" => context.trigger,
          "context_scope" => context_scope(context),
          "tools_executed" => tools.executed_tools,
          "evidence" => tools.evidence.values,
          "candidate_decision" => candidate,
          "grounded_decision" => grounded,
          "validation" => { "valid" => false, "errors" => errors },
          "effect_execution" => { "performed" => false },
          "latency_ms" => elapsed_ms(started_at)
        }
      end

      def skipped_result(reason)
        { "status" => "skipped", "activity_summary" => reason, "architecture_version" => "grounded_v1" }
      end

      def legacy_context(context)
        { task: task, user: context.professional, client: context.client, session: context.session, recent_messages: [] }
      end

      def context_scope(context)
        {
          "workspace_id" => context.workspace.id,
          "professional_id" => context.professional.id,
          "client_id" => context.client.id,
          "session_id" => context.session&.id,
          "message_id" => context.message.id
        }.compact
      end

      def elapsed_ms(started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      end
    end
  end
end
