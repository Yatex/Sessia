require "test_helper"

class AiSettingTest < ActiveSupport::TestCase
  test "requires professional WhatsApp when custom AI WhatsApp is enabled" do
    user = User.create!(name: "AI Pro", email: "ai-pro@example.com", password: "password123")
    setting = user.ai_setting
    setting.use_professional_whatsapp = true
    setting.professional_whatsapp_phone = ""

    assert_not setting.valid?
    assert_includes setting.errors[:professional_whatsapp_phone], "can't be blank"
  end

  test "normalizes professional WhatsApp phone" do
    user = User.create!(name: "WhatsApp Pro", email: "whatsapp-pro@example.com", password: "password123")
    setting = user.ai_setting
    setting.update!(use_professional_whatsapp: true, professional_whatsapp_phone: "  +598 99 000 111  ")

    assert_equal "+598 99 000 111", setting.professional_whatsapp_phone
  end
end
