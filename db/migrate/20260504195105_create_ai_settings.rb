class CreateAiSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :confirm_sessions, null: false, default: true
      t.boolean :send_pre_session_reminders, null: false, default: true
      t.boolean :follow_up_no_response, null: false, default: true
      t.boolean :ask_feedback_after_sessions, null: false, default: true
      t.boolean :answer_basic_questions, null: false, default: true
      t.boolean :escalate_important_conversations, null: false, default: true
      t.boolean :payment_reminders, null: false, default: false
      t.text :instructions

      t.timestamps
    end
  end
end
