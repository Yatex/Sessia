class CreatePaymentRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_records do |t|
      t.references :user, null: false, foreign_key: true
      t.references :client, null: true, foreign_key: true
      t.references :session, null: true, foreign_key: true
      t.integer :amount_cents, null: false, default: 0
      t.string :currency, null: false, default: "USD"
      t.integer :status, null: false, default: 0
      t.date :due_on
      t.datetime :paid_at
      t.text :notes

      t.timestamps
    end

    add_index :payment_records, [:user_id, :status]
    add_index :payment_records, [:user_id, :due_on]
  end
end
