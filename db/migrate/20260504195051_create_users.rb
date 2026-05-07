class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :password_reset_token_digest
      t.datetime :password_reset_sent_at
      t.string :time_zone, null: false, default: "America/Montevideo"
      t.string :stripe_customer_id

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :password_reset_token_digest, unique: true
    add_index :users, :stripe_customer_id
  end
end
