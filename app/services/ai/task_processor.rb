module Ai
  class TaskProcessor
    def initialize(task:, decision_client: DecisionServiceClient.new, dispatcher: Messaging::Dispatcher.new)
      @task = task
      @decision_client = decision_client
      @dispatcher = dispatcher
    end

    def call
      return task if task.status_completed? || task.status_skipped?

      task.update!(status: "processing", error_message: nil)

      current_stage = "context_building"
      if grounded_inbound_task?
        grounded_result = Ai::Grounded::TaskProcessor.new(
          task: task,
          decision_client: decision_client,
          dispatcher: dispatcher
        ).call
        finalize!(grounded_result.fetch("status"), grounded_result, error_message: grounded_result["error_message"])
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
      current_stage = "action_execution"
      executor_result = Ai::ActionExecutor.new(
        task: task,
        context: context,
        instruction: instruction,
        dispatcher: dispatcher
      ).call(decision)

      finalize!(
        executor_result.status,
        decision.merge(executor_result.to_h).merge(failure_details_for(executor_result, current_stage))
      )
      task
    rescue StandardError => error
      Rails.logger.warn("Sessia AI task #{task.id} failed: #{error.class}: #{error.message}")
      finalize!("failed", {
        "activity_summary" => "AI task failed.",
        "reasoning_summary" => error.message,
        "failure_details" => {
          "stage" => defined?(current_stage) ? current_stage : "task_processing",
          "error_class" => error.class.name,
          "error_message" => error.message.to_s
        }
      }, error_message: error.message)
      task
    end

    private

    attr_reader :task, :decision_client, :dispatcher

    def grounded_inbound_task?
      task.trigger_event == "client_replied" && Ai::Grounded::Feature.inbound_enabled?
    end

    def finalize!(status, result_data, error_message: nil)
      task.update!(
        status: status,
        processed_at: Time.current,
        result_data: result_data,
        error_message: error_message
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
