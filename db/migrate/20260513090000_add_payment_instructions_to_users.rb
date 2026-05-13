class AddPaymentInstructionsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :payment_instructions, :text
  end
end
