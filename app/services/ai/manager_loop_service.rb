module Ai
  class ManagerLoopService
    Result = Struct.new(:generated_count, :processed_count, :completed_count, :skipped_count, :failed_count, :errors, keyword_init: true) do
      def summary
        "#{generated_count} generated, #{processed_count} processed, #{completed_count} completed, #{skipped_count} skipped, #{failed_count} failed."
      end
    end

    def initialize(users: User.all, now: Time.current, decision_client: DecisionServiceClient.new)
      @users = users
      @now = now
      @decision_client = decision_client
    end

    def call
      generated = Ai::TaskGenerator.new(users: users, now: now).call
      processed = []
      errors = []

      due_scope.find_each do |task|
        processed_task = Ai::TaskProcessor.new(task: task, decision_client: decision_client).call.reload
        processed << processed_task
        errors << "Task ##{task.id}: #{processed_task.error_message}" if processed_task.status_failed? && processed_task.error_message.present?
      rescue StandardError => error
        errors << "Task ##{task.id}: #{error.message}"
      end

      Result.new(
        generated_count: generated.count,
        processed_count: processed.count,
        completed_count: processed.count(&:status_completed?),
        skipped_count: processed.count(&:status_skipped?),
        failed_count: processed.count(&:status_failed?),
        errors: errors
      )
    end

    private

    attr_reader :users, :now, :decision_client

    def user_scope
      users.respond_to?(:find_each) ? users : User.where(id: Array(users).map(&:id))
    end

    def due_scope
      AiTask.due.where(user_id: user_scope.select(:id)).includes(:user, :client, :session)
    end
  end
end
