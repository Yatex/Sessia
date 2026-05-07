class AddAiMetadataToMessages < ActiveRecord::Migration[7.1]
  def change
    add_reference :messages, :ai_task, foreign_key: true
    add_column :messages, :metadata, :jsonb, null: false, default: {}
    add_column :messages, :external_id, :string
    add_column :messages, :error_message, :text

    add_index :messages, [:user_id, :direction, :created_at]
    add_index :messages, :external_id
  end
end
