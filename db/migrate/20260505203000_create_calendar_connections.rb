class CreateCalendarConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :calendar_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false, default: "google"
      t.string :provider_account_email
      t.string :calendar_id, null: false, default: "primary"
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext
      t.datetime :access_token_expires_at
      t.boolean :sync_sessions, null: false, default: true
      t.integer :status, null: false, default: 0
      t.datetime :last_synced_at
      t.text :error_message

      t.timestamps
    end

    add_index :calendar_connections, [:user_id, :provider], unique: true
    add_index :calendar_connections, :status
  end
end
