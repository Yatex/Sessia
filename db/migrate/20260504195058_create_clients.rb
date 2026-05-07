class CreateClients < ActiveRecord::Migration[7.1]
  def change
    create_table :clients do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.integer :status, null: false, default: 0
      t.string :preferred_contact_channel, null: false, default: "email"
      t.text :notes

      t.timestamps
    end

    add_index :clients, [:user_id, :status]
    add_index :clients, [:user_id, :email]
  end
end
