require "test_helper"

class MessagingDispatcherTest < ActiveSupport::TestCase
  class UnconfiguredProvider
    def configured?
      false
    end
  end

  class ConfiguredProvider
    attr_reader :deliveries

    def initialize
      @deliveries = []
    end

    def configured?
      true
    end

    def deliver(to:, body:, template: nil)
      deliveries << { to: to, body: body, template: template }
      {
        provider: "twilio_whatsapp",
        external_id: "SM-test-#{deliveries.size}",
        status: "queued"
      }
    end
  end

  class FailingProvider
    def configured?
      true
    end

    def deliver(to:, body:, template: nil)
      raise Messaging::TwilioWhatsappProvider::DeliveryError.new(
        "Twilio WhatsApp send failed: The Content Variables parameter is invalid.",
        provider_metadata: {
          name: "twilio_whatsapp",
          status: "failed",
          error_code: 21656,
          template: template,
          request: {
            content_sid: template&.dig("content_sid"),
            content_variables: template&.dig("variables").to_json
          }
        }
      )
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

  test "uses approved whatsapp template for proactive messages outside response window" do
    user = User.create!(name: "Messaging Pro", email: "messaging-template@example.com", password: "password123", locale: "en")
    client = user.clients.create!(name: "Client", phone: "+598 99 111 227")
    session = user.sessions.create!(
      client: client,
      title: "Coaching",
      start_time: Time.zone.local(2026, 5, 12, 10, 0),
      end_time: Time.zone.local(2026, 5, 12, 11, 0)
    )
    task = user.ai_tasks.create!(
      client: client,
      session: session,
      trigger_event: "before_session",
      automation_key: "confirm_session",
      scheduled_for: Time.current
    )
    provider = ConfiguredProvider.new

    message = Messaging::Dispatcher.new(provider: provider).deliver(
      user: user,
      client: client,
      session: session,
      ai_task: task,
      body: "Please confirm your session.",
      metadata: { "source" => "ai" }
    )

    template = provider.deliveries.first[:template]
    assert_equal "session_confirmation_en", template["name"]
    assert_equal "HX88edb7ea06c9c6b8f992ee87489e64ca", template["content_sid"]
    assert_equal "Client", template["variables"]["1"]
    assert_equal "Coaching", template["variables"]["2"]
    assert_equal "sent", message.status
    assert_equal "queued", message.metadata.dig("provider", "status")
    assert_equal "session_confirmation_en", message.metadata.dig("whatsapp_template", "name")
  end

  test "uses free form whatsapp body inside response window" do
    user = User.create!(name: "Messaging Pro", email: "messaging-window@example.com", password: "password123")
    client = user.clients.create!(name: "Client", phone: "+598 99 111 228")
    client.messages.create!(
      user: user,
      direction: "inbound",
      channel: "whatsapp",
      status: "sent",
      subject: "WhatsApp reply",
      body: "hello",
      sent_at: 10.minutes.ago
    )
    task = user.ai_tasks.create!(
      client: client,
      trigger_event: "before_session",
      automation_key: "payment_reminder",
      scheduled_for: Time.current
    )
    provider = ConfiguredProvider.new

    message = Messaging::Dispatcher.new(provider: provider).deliver(
      user: user,
      client: client,
      ai_task: task,
      body: "Thanks, here is the payment reminder.",
      metadata: { "source" => "ai" }
    )

    assert_nil provider.deliveries.first[:template]
    assert_nil message.metadata["whatsapp_template"]
    assert_equal "Thanks, here is the payment reminder.", provider.deliveries.first[:body]
  end

  test "stores provider diagnostics when template delivery fails" do
    user = User.create!(name: "Messaging Pro", email: "messaging-failure@example.com", password: "password123", locale: "en")
    client = user.clients.create!(name: "Client", phone: "+598 99 111 229")
    session = user.sessions.create!(
      client: client,
      title: "Coaching",
      start_time: Time.zone.local(2026, 5, 12, 10, 0),
      end_time: Time.zone.local(2026, 5, 12, 11, 0)
    )
    task = user.ai_tasks.create!(
      client: client,
      session: session,
      trigger_event: "before_session",
      automation_key: "confirm_session",
      scheduled_for: Time.current
    )

    assert_raises(Messaging::TwilioWhatsappProvider::DeliveryError) do
      Messaging::Dispatcher.new(provider: FailingProvider.new).deliver(
        user: user,
        client: client,
        session: session,
        ai_task: task,
        body: "Please confirm.",
        metadata: { "source" => "ai" }
      )
    end

    message = user.messages.outbound.last
    assert_equal "failed", message.status
    assert_equal "session_confirmation_en", message.metadata.dig("provider", "template", "name")
    assert_equal "21656", message.metadata.dig("provider", "error_code").to_s
    assert_match "Content Variables", message.error_message
  end
end
