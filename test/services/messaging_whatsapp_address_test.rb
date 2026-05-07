require "test_helper"

class MessagingWhatsappAddressTest < ActiveSupport::TestCase
  test "normalizes twilio whatsapp addresses and local phone formatting" do
    assert_equal "59899111222", Messaging::WhatsappAddress.normalize("whatsapp:+598 99 111 222")
    assert_equal "59899111222", Messaging::WhatsappAddress.normalize("+598 99 111 222")
    assert Messaging::WhatsappAddress.same?("whatsapp:+59899111222", "+598 99 111 222")
  end

  test "formats a number for twilio whatsapp delivery" do
    assert_equal "whatsapp:+59899111222", Messaging::WhatsappAddress.twilio_address("+598 99 111 222")
    assert_equal "whatsapp:+14155238886", Messaging::WhatsappAddress.twilio_address("whatsapp:+14155238886")
  end
end
