require "test_helper"

class ClientTest < ActiveSupport::TestCase
  test "requires a WhatsApp phone number" do
    user = User.create!(name: "Owner", email: "client-owner@example.com", password: "password123")
    client = user.clients.new(name: "Client", email: "client-phone@example.com")

    assert_not client.valid?
    assert_includes client.errors[:phone], "can't be blank"
  end

  test "forces WhatsApp as the only preferred channel" do
    user = User.create!(name: "Owner", email: "client-owner-2@example.com", password: "password123")
    client = user.clients.create!(
      name: "Client",
      email: "client-channel@example.com",
      phone: "+598 99 123 456",
      preferred_contact_channel: "email"
    )

    assert_equal "whatsapp", client.preferred_contact_channel
  end

  test "generates a portal token" do
    user = User.create!(name: "Owner", email: "client-owner-3@example.com", password: "password123")
    client = user.clients.create!(name: "Client", phone: "+598 99 123 457")

    assert client.portal_token.present?
  end
end
