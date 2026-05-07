class CreateMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :messages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :client, null: true, foreign_key: true
      t.references :session, null: true, foreign_key: true
      t.integer :direction, null: false, default: 0
      t.string :channel, null: false, default: "email"
      t.integer :status, null: false, default: 0
      t.string :subject
      t.text :body
      t.datetime :sent_at

      t.timestamps
    end

    add_index :messages, [:user_id, :status]
    add_index :messages, [:client_id, :created_at]
  end
end
