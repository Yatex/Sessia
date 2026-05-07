class AddPricingToSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :sessions, :price_cents, :integer, null: false, default: 0
    add_column :sessions, :currency, :string, null: false, default: "USD"
    change_column_default :sessions, :payment_status, from: 0, to: 1
  end
end
