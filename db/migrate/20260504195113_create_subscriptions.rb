class CreateSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :plan_tier, null: false, default: "starter"
      t.integer :status, null: false, default: 0
      t.string :provider, null: false, default: "stripe"
      t.string :provider_subscription_id
      t.string :provider_plan_id
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :trial_ends_at
      t.boolean :cancel_at_period_end, null: false, default: false
      t.integer :quantity, null: false, default: 1

      t.timestamps
    end

    add_index :subscriptions, [:user_id, :status]
    add_index :subscriptions, [:provider, :provider_subscription_id], unique: true
    add_index :subscriptions, :provider_plan_id
  end
end
