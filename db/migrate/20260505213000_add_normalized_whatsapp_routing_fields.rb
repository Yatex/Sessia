class AddNormalizedWhatsappRoutingFields < ActiveRecord::Migration[7.1]
  def up
    add_column :clients, :phone_normalized, :string
    add_index :clients, [:phone_normalized, :user_id]

    execute <<~SQL.squish
      UPDATE clients
      SET phone_normalized = regexp_replace(phone, '[^0-9]', '', 'g')
    SQL

    add_index :messages,
      :external_id,
      unique: true,
      where: "external_id IS NOT NULL",
      name: "index_messages_on_external_id_unique"
  end

  def down
    remove_index :messages, name: "index_messages_on_external_id_unique"
    remove_index :clients, [:phone_normalized, :user_id]
    remove_column :clients, :phone_normalized
  end
end
