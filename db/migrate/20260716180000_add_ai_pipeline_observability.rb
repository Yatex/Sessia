class AddAiPipelineObservability < ActiveRecord::Migration[7.1]
  def up
    change_table :ai_tasks, bulk: true do |t|
      t.string :idempotency_key
      t.string :trace_id
      t.string :decision_status
      t.string :validation_status
      t.string :execution_status
      t.string :delivery_status
      t.string :error_category
      t.integer :retry_count, default: 0, null: false
      t.datetime :next_retry_at
      t.datetime :last_error_at
      t.datetime :claimed_at
    end

    add_index :ai_tasks, :idempotency_key, unique: true,
      where: "idempotency_key IS NOT NULL",
      name: "index_ai_tasks_on_idempotency_key_unique"
    add_index :ai_tasks, [:status, :scheduled_for, :next_retry_at],
      name: "index_ai_tasks_on_pipeline_schedule"
    add_index :ai_tasks, :trace_id, unique: true,
      where: "trace_id IS NOT NULL"

    create_table :ai_traces do |t|
      t.references :ai_task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :client, foreign_key: true
      t.references :session, foreign_key: true
      t.string :trace_id, null: false
      t.string :idempotency_key
      t.string :trigger
      t.string :channel
      t.string :prompt_version
      t.string :schema_version
      t.string :provider
      t.string :model
      t.string :decision_status
      t.string :validation_status
      t.string :execution_status
      t.string :delivery_status
      t.string :error_category
      t.boolean :fallback_used, default: false, null: false
      t.integer :latency_ms
      t.jsonb :context_scope, default: {}, null: false
      t.jsonb :allowed_actions, default: [], null: false
      t.jsonb :tools_requested, default: [], null: false
      t.jsonb :tools_completed, default: [], null: false
      t.jsonb :tool_errors, default: [], null: false
      t.jsonb :evidence_found, default: [], null: false
      t.jsonb :evidence_used, default: [], null: false
      t.jsonb :candidate_decision, default: {}, null: false
      t.jsonb :validation_results, default: {}, null: false
      t.jsonb :final_decision, default: {}, null: false
      t.jsonb :execution_result, default: {}, null: false
      t.jsonb :delivery_result, default: {}, null: false
      t.timestamps
    end
    add_index :ai_traces, :trace_id, unique: true
    add_index :ai_traces, [:user_id, :created_at]
    add_index :ai_traces, [:delivery_status, :created_at]

    create_table :message_delivery_attempts do |t|
      t.references :message, null: false, foreign_key: true
      t.references :ai_task, foreign_key: true
      t.integer :attempt_number, null: false
      t.string :status, null: false
      t.string :error_category
      t.boolean :retryable, default: false, null: false
      t.datetime :next_retry_at
      t.string :provider_message_id
      t.string :provider_error_code
      t.text :provider_error_message
      t.jsonb :request_data, default: {}, null: false
      t.jsonb :response_data, default: {}, null: false
      t.timestamps
    end
    add_index :message_delivery_attempts, [:message_id, :attempt_number], unique: true,
      name: "index_delivery_attempts_on_message_and_number"
    add_index :message_delivery_attempts, [:retryable, :next_retry_at],
      name: "index_delivery_attempts_on_retry_schedule"
  end

  def down
    drop_table :message_delivery_attempts
    drop_table :ai_traces
    remove_index :ai_tasks, name: "index_ai_tasks_on_pipeline_schedule"
    remove_index :ai_tasks, name: "index_ai_tasks_on_idempotency_key_unique"
    remove_index :ai_tasks, :trace_id
    remove_columns :ai_tasks, :idempotency_key, :trace_id, :decision_status,
      :validation_status, :execution_status, :delivery_status, :error_category,
      :retry_count, :next_retry_at, :last_error_at, :claimed_at
  end
end
