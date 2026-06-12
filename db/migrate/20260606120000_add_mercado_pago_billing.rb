class AddMercadoPagoBilling < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false, default: "mercado_pago"
      t.string :provider_user_id
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext
      t.datetime :token_expires_at
      t.integer :status, null: false, default: 0
      t.datetime :connected_at
      t.text :last_error

      t.timestamps
    end
    add_index :payment_accounts, [:user_id, :provider], unique: true
    add_index :payment_accounts, [:provider, :provider_user_id]
    add_index :payment_accounts, :status

    create_table :client_billing_profiles do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.references :user, null: false, foreign_key: true
      t.integer :default_session_price_cents, null: false, default: 0
      t.string :currency, null: false, default: "ARS"
      t.boolean :payment_required_before_session, null: false, default: false
      t.integer :default_due_timing, null: false, default: 0
      t.integer :custom_due_days_before
      t.boolean :active, null: false, default: true
      t.text :notes

      t.timestamps
    end
    add_index :client_billing_profiles, [:user_id, :active]

    create_table :charges do |t|
      t.references :client, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :session, null: true, foreign_key: true, index: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "ARS"
      t.string :concept, null: false
      t.text :description
      t.date :due_date
      t.integer :status, null: false, default: 0
      t.integer :generated_by, null: false, default: 0
      t.string :external_reference, null: false
      t.string :mercado_pago_preference_id
      t.text :mercado_pago_init_point
      t.text :mercado_pago_sandbox_init_point
      t.text :payment_url
      t.datetime :paid_at
      t.datetime :cancelled_at

      t.timestamps
    end
    add_index :charges, :external_reference, unique: true
    add_index :charges, [:user_id, :status]
    add_index :charges, [:user_id, :due_date]
    add_index :charges, [:session_id], unique: true, where: "session_id IS NOT NULL"
    add_index :charges, :mercado_pago_preference_id

    create_table :payments do |t|
      t.references :charge, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false, default: "mercado_pago"
      t.string :provider_payment_id
      t.integer :amount_cents, null: false, default: 0
      t.string :currency, null: false, default: "ARS"
      t.integer :status, null: false, default: 0
      t.string :status_detail
      t.datetime :paid_at
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end
    add_index :payments, [:provider, :provider_payment_id], unique: true, where: "provider_payment_id IS NOT NULL"
    add_index :payments, [:user_id, :status]
    add_index :payments, [:charge_id, :status]

    create_table :credit_ledger_entries do |t|
      t.references :client, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "ARS"
      t.integer :entry_type, null: false
      t.string :reason
      t.references :related_payment, null: true, foreign_key: { to_table: :payments }
      t.references :related_charge, null: true, foreign_key: { to_table: :charges }
      t.references :related_session, null: true, foreign_key: { to_table: :sessions }
      t.references :created_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end
    add_index :credit_ledger_entries, [:user_id, :created_at]
    add_index :credit_ledger_entries, [:client_id, :created_at]

    create_table :audit_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :event, null: false
      t.string :auditable_type
      t.bigint :auditable_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :audit_logs, [:user_id, :event, :created_at]
    add_index :audit_logs, [:auditable_type, :auditable_id]

    add_reference :sessions, :charge, null: true, foreign_key: true
    add_column :sessions, :payment_required_before_session, :boolean, null: false, default: false
    change_column_default :sessions, :currency, from: "USD", to: "ARS"
  end
end
