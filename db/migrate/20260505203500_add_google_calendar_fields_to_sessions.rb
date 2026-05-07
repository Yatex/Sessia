class AddGoogleCalendarFieldsToSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :sessions, :sync_to_google_calendar, :boolean, null: false, default: false
    add_column :sessions, :google_calendar_event_id, :string
    add_column :sessions, :google_calendar_synced_at, :datetime
    add_column :sessions, :google_calendar_sync_error, :text

    add_index :sessions, [:user_id, :sync_to_google_calendar]
    add_index :sessions, [:user_id, :google_calendar_event_id]
  end
end
