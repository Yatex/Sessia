class AddProfessionalWhatsappToAiSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_settings, :use_professional_whatsapp, :boolean, null: false, default: false
    add_column :ai_settings, :professional_whatsapp_phone, :string
  end
end
