class CreateAiTasksAndAlerts < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :client, foreign_key: true
      t.references :session, foreign_key: true
      t.string :trigger_event, null: false
      t.string :automation_key
      t.string :status, null: false, default: "pending"
      t.datetime :scheduled_for, null: false
      t.datetime :processed_at
      t.jsonb :context_data, null: false, default: {}
      t.jsonb :result_data, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :ai_tasks, [:user_id, :status, :scheduled_for]
    add_index :ai_tasks, [:user_id, :trigger_event]
    add_index :ai_tasks, [:session_id, :automation_key]

    create_table :ai_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :client, foreign_key: true
      t.references :session, foreign_key: true
      t.references :ai_task, foreign_key: true
      t.string :status, null: false, default: "open"
      t.string :severity, null: false, default: "medium"
      t.string :title, null: false
      t.text :body, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :ai_alerts, [:user_id, :status, :created_at]
  end
end
