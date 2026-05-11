class AddGoogleIdentityToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :google_uid, :string
    add_column :users, :google_avatar_url, :string

    add_index :users, :google_uid, unique: true, where: "google_uid IS NOT NULL"
  end
end
