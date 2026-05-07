class AddStructuredRecurrenceToSessions < ActiveRecord::Migration[7.1]
  def change
    add_reference :sessions, :parent_session, foreign_key: { to_table: :sessions }, index: true
    add_column :sessions, :recurrence_frequency, :string, null: false, default: "none"
    add_column :sessions, :recurrence_days, :integer, array: true, null: false, default: []
    add_column :sessions, :recurrence_ends_on, :date
    add_column :sessions, :recurrence_generated_until, :date
    add_index :sessions, [:user_id, :parent_session_id]
    add_index :sessions, [:user_id, :recurrence_frequency]
  end
end
