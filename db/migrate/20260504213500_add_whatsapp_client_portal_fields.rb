class AddWhatsappClientPortalFields < ActiveRecord::Migration[7.1]
  def up
    add_column :clients, :portal_token, :string
    add_column :clients, :linked_at, :datetime

    execute "UPDATE clients SET preferred_contact_channel = 'whatsapp'"
    execute "UPDATE clients SET phone = '' WHERE phone IS NULL"

    change_column_default :clients, :preferred_contact_channel, from: "email", to: "whatsapp"
    change_column_null :clients, :phone, false

    Client.reset_column_information
    Client.find_each do |client|
      client.update_columns(portal_token: unique_portal_token) if client.portal_token.blank?
    end

    change_column_null :clients, :portal_token, false
    add_index :clients, :portal_token, unique: true
    add_index :clients, :linked_at
  end

  def down
    remove_index :clients, :linked_at
    remove_index :clients, :portal_token
    change_column_null :clients, :phone, true
    change_column_default :clients, :preferred_contact_channel, from: "whatsapp", to: "email"
    remove_column :clients, :linked_at
    remove_column :clients, :portal_token
  end

  private

  def unique_portal_token
    loop do
      token = SecureRandom.urlsafe_base64(32)
      break token unless Client.exists?(portal_token: token)
    end
  end
end
