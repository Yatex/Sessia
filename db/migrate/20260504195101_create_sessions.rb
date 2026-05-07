class CreateSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.string :title, null: false
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.integer :status, null: false, default: 0
      t.integer :confirmation_status, null: false, default: 0
      t.integer :payment_status, null: false, default: 0
      t.boolean :recurring, null: false, default: false
      t.string :recurrence_rule
      t.text :notes

      t.timestamps
    end

    add_index :sessions, [:user_id, :start_time]
    add_index :sessions, [:client_id, :start_time]
    add_index :sessions, [:user_id, :confirmation_status]
    add_index :sessions, [:user_id, :payment_status]
  end
end
