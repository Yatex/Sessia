module Ai
  class TaskProcessor
    def initialize(task:, decision_client: DecisionServiceClient.new, dispatcher: Messaging::Dispatcher.new)
      @task = task
      @decision_client = decision_client
      @dispatcher = dispatcher
    end

    def call
      return task if task.status_completed? || task.status_skipped?
      task.update!(trace_id: SecureRandom.uuid) if task.trace_id.blank?
      return task unless task.claim!

      trace = start_trace

      current_stage = "context_building"
      if grounded_task?
        grounded_result = Ai::Grounded::TaskProcessor.new(
          task: task,
          decision_client: decision_client,
          dispatcher: dispatcher
        ).call
        finalize_grounded!(grounded_result, trace)
        return task
      end

      context = Ai::ContextBuilder.new(task: task).call
      current_stage = "instruction_matching"
      instruction = Ai::InstructionCatalog.for_task(task, ai_setting: task.user.ai_setting || task.user.create_ai_setting!)

      if instruction.blank?
        finalize!("skipped", {
          "activity_summary" => "No enabled AI instruction matched this task.",
          "reasoning_summary" => "Skipped because #{task.trigger_event} is disabled in AI settings."
        })
        return task
      end

      current_stage = "provider_decision"
      payload = context.fetch(:payload).merge(instruction: instruction.to_h)
      decision = decision_client.decide(payload)
      task.update!(decision_status: "completed", validation_status: "not_required")
      current_stage = "action_execution"
      executor_result = Ai::ActionExecutor.new(
        task: task,
        context: context,
        instruction: instruction,
        dispatcher: dispatcher
      ).call(decision)

      finalize!(
        executor_result.status,
        decision.merge(executor_result.to_h).merge(failure_details_for(executor_result, current_stage)),
        error_message: executor_result.error_message
      )
      update_trace(trace, decision: decision, executor_result: executor_result)
      task
    rescue StandardError => error
      Rails.logger.warn("Sessia AI task #{task.id} failed: #{error.class}: #{error.message}")
      classification = Ai::ErrorClassifier.call(error)
      finalize!("failed", {
        "activity_summary" => "AI task failed.",
        "reasoning_summary" => error.message,
        "failure_details" => {
          "stage" => defined?(current_stage) ? current_stage : "task_processing",
          "error_class" => error.class.name,
          "error_message" => error.message.to_s
        }
      }, error_message: error.message, pipeline: {
        decision_status: current_stage == "provider_decision" ? "failed" : task.decision_status,
        validation_status: task.validation_status,
        execution_status: current_stage == "action_execution" ? "failed" : "not_required",
        error_category: classification.category
      })
      trace&.update!(decision_status: task.decision_status, validation_status: task.validation_status, execution_status: task.execution_status, delivery_status: task.delivery_status, error_category: classification.category)
      task
    end

    private

    attr_reader :task, :decision_client, :dispatcher

    def grounded_task?
      (task.trigger_event == "client_replied" && Ai::Grounded::Feature.inbound_enabled?) ||
        (task.trigger_event == "before_session" && task.automation_key == "confirm_session" && Ai::Grounded::Feature.before_session_v2_enabled?)
    end

    def finalize!(status, result_data, error_message: nil, pipeline: {})
      executor_status = result_data["execution_status"]
      delivery_status = result_data["delivery_status"]
      task.update!(
        status: status,
        processed_at: Time.current,
        result_data: result_data,
        error_message: error_message,
        decision_status: pipeline[:decision_status] || task.decision_status,
        validation_status: pipeline[:validation_status] || task.validation_status,
        execution_status: pipeline[:execution_status] || executor_status || task.execution_status,
        delivery_status: pipeline[:delivery_status] || delivery_status || task.delivery_status,
        error_category: pipeline[:error_category] || result_data["error_category"] || task.error_category,
        last_error_at: error_message.present? ? Time.current : task.last_error_at
      )
    end

    def start_trace
      task.ai_traces.create!(
        user: task.user, client: task.client, session: task.session,
        trace_id: task.trace_id || SecureRandom.uuid,
        idempotency_key: task.idempotency_key, trigger: task.trigger_event,
        channel: Client::WHATSAPP_CHANNEL,
        prompt_version: grounded_task? ? "sessia_grounded_v2" : "sessia_legacy_v1",
        schema_version: grounded_task? ? "decision_v2" : "decision_v1",
        decision_status: "processing", validation_status: "pending",
        execution_status: "pending", delivery_status: "pending",
        context_scope: { workspace_id: task.user.studio_id || task.user_id, professional_id: task.user_id, client_id: task.client_id, session_id: task.session_id },
        allowed_actions: []
      )
    rescue ActiveRecord::RecordNotUnique
      task.ai_traces.find_by!(trace_id: task.trace_id)
    end

    def finalize_grounded!(result, trace)
      validation_status = result.dig("validation", "valid") == false ? "rejected" : "accepted"
      task.update!(decision_status: result["candidate_decision"].present? ? "completed" : "failed", validation_status: validation_status)
      finalize!(result.fetch("status"), result, error_message: result["error_message"], pipeline: {
        decision_status: task.decision_status,
        validation_status: validation_status,
        execution_status: result.dig("effect_execution", "execution_status") || (validation_status == "rejected" ? "not_required" : result["status"] == "failed" ? "failed" : "completed"),
        delivery_status: result.dig("effect_execution", "delivery_status") || task.delivery_status,
        error_category: validation_status == "rejected" ? "validation_rejected" : result["error_category"]
      })
      trace.update!(
        decision_status: task.decision_status, validation_status: task.validation_status,
        execution_status: task.execution_status, delivery_status: task.delivery_status,
        error_category: task.error_category, tools_requested: result["tools_requested"] || result["tools_executed"],
        tools_completed: result["tools_completed"] || result["tools_executed"], tool_errors: result["tool_errors"] || [],
        evidence_found: result["evidence"] || [], evidence_used: result.dig("grounded_decision", "evidence_ids") || [],
        candidate_decision: result["candidate_decision"] || {}, validation_results: result["validation"] || {},
        final_decision: result["grounded_decision"] || {}, execution_result: result["effect_execution"] || {},
        delivery_result: task.latest_outbound_message&.metadata.to_h.dig("provider") || {}, latency_ms: result["latency_ms"],
        provider: result.dig("decision_metadata", "provider"), model: result.dig("decision_metadata", "model"),
        prompt_version: result.dig("decision_metadata", "promptVersion") || trace.prompt_version,
        schema_version: result.dig("decision_metadata", "schemaVersion") || trace.schema_version
      )
    end

    def update_trace(trace, decision:, executor_result:)
      trace.update!(
        decision_status: task.decision_status, validation_status: task.validation_status,
        execution_status: task.execution_status, delivery_status: task.delivery_status,
        error_category: task.error_category, candidate_decision: decision,
        validation_results: { status: task.validation_status }, final_decision: decision,
        execution_result: executor_result.to_h,
        delivery_result: task.latest_outbound_message&.metadata.to_h.dig("provider") || {}
      )
    end

    def failure_details_for(executor_result, stage)
      return {} unless executor_result.status == "failed"

      {
        "failure_details" => {
          "stage" => stage,
          "error_message" => executor_result.error_message.to_s
        }
      }
    end
  end
end
