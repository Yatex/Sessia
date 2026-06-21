class AddStudioAccountsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :account_type, :integer, null: false, default: 0
    add_reference :users, :studio, foreign_key: { to_table: :users }, index: true
    add_index :users, [:studio_id, :account_type]
  end
end
