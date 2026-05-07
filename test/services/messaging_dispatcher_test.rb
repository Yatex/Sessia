require "test_helper"

class MessagingDispatcherTest < ActiveSupport::TestCase
  class UnconfiguredProvider
    def configured?
      false
    end
  end

  test "queues outbound whatsapp message when provider is not configured" do
    user = User.create!(name: "Messaging Pro", email: "messaging@example.com", password: "password123")
    client = user.clients.create!(name: "Client", phone: "+598 99 111 226")

    message = Messaging::Dispatcher.new(provider: UnconfiguredProvider.new).deliver(
      user: user,
      client: client,
      body: "Hello",
      metadata: { "source" => "ai" }
    )

    assert_equal "outbound", message.direction
    assert_equal "queued", message.status
    assert_equal "whatsapp", message.channel
    assert_equal "ai", message.metadata["source"]
  end
end
