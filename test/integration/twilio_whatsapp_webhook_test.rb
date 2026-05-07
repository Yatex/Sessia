require "test_helper"

class TwilioWhatsappWebhookTest < ActionDispatch::IntegrationTest
  test "accepts inbound whatsapp reply and stores it for the matching client" do
    user = User.create!(name: "Webhook Pro", email: "twilio-webhook@example.com", password: "password123")
    disable_ai_for(user)
    client = user.clients.create!(name: "Webhook Client", phone: "+598 99 111 230")

    assert_difference -> { user.messages.inbound.count }, 1 do
      post twilio_whatsapp_webhook_url, params: {
        From: "whatsapp:+59899111230",
        To: "whatsapp:+14155238886",
        Body: "I confirm",
        MessageSid: "SM-webhook-1"
      }
    end

    assert_response :ok
    message = user.messages.last
    assert_equal client, message.client
    assert_equal "I confirm", message.body
    assert_equal "twilio_whatsapp", message.metadata.dig("source")
  end

  test "deduplicates twilio retries by message sid" do
    user = User.create!(name: "Webhook Pro", email: "twilio-dedupe@example.com", password: "password123")
    disable_ai_for(user)
    user.clients.create!(name: "Webhook Client", phone: "+598 99 111 231")
    params = {
      From: "whatsapp:+59899111231",
      To: "whatsapp:+14155238886",
      Body: "Question",
      MessageSid: "SM-webhook-dedupe"
    }

    assert_difference -> { user.messages.inbound.count }, 1 do
      2.times do
        post twilio_whatsapp_webhook_url, params: params
        assert_response :ok
      end
    end
  end

  test "rejects invalid twilio signature when verification is required" do
    with_env("TWILIO_AUTH_TOKEN" => "secret", "TWILIO_VERIFY_WEBHOOK_SIGNATURE" => "true") do
      assert_no_difference -> { Message.count } do
        post twilio_whatsapp_webhook_url,
          params: {
            From: "whatsapp:+59899111232",
            To: "whatsapp:+14155238886",
            Body: "Hello",
            MessageSid: "SM-bad-signature"
          },
          headers: { "X-Twilio-Signature" => "bad" }
      end
    end

    assert_response :unauthorized
  end

  test "accepts valid twilio signature when verification is required" do
    user = User.create!(name: "Webhook Pro", email: "twilio-signature@example.com", password: "password123")
    disable_ai_for(user)
    user.clients.create!(name: "Webhook Client", phone: "+598 99 111 233")
    webhook_url = twilio_whatsapp_webhook_url
    params = {
      "From" => "whatsapp:+59899111233",
      "To" => "whatsapp:+14155238886",
      "Body" => "Confirmed",
      "MessageSid" => "SM-good-signature"
    }

    with_env(
      "TWILIO_AUTH_TOKEN" => "secret",
      "TWILIO_VERIFY_WEBHOOK_SIGNATURE" => "true",
      "TWILIO_WEBHOOK_URL" => webhook_url
    ) do
      signature = Messaging::TwilioSignatureVerifier.new(auth_token: "secret").expected_signature(url: webhook_url, params: params)

      assert_difference -> { user.messages.inbound.count }, 1 do
        post twilio_whatsapp_webhook_url, params: params, headers: { "X-Twilio-Signature" => signature }
      end
    end

    assert_response :ok
  end

  test "records whatsapp provider delivery status callbacks" do
    user = User.create!(name: "Webhook Pro", email: "twilio-status@example.com", password: "password123")
    client = user.clients.create!(name: "Webhook Client", phone: "+598 99 111 234")
    task = user.ai_tasks.create!(
      client: client,
      trigger_event: "before_session",
      automation_key: "confirm_session",
      scheduled_for: Time.current
    )
    outbound = user.messages.create!(
      client: client,
      ai_task: task,
      direction: "outbound",
      channel: "whatsapp",
      status: "sent",
      subject: "Confirmation",
      body: "Can you confirm?",
      sent_at: Time.current,
      external_id: "SM-status-callback",
      metadata: { "source" => "ai" }
    )

    assert_no_difference -> { user.messages.inbound.count } do
      post twilio_whatsapp_webhook_url, params: {
        MessageSid: "SM-status-callback",
        MessageStatus: "undelivered",
        ErrorCode: "63016",
        ErrorMessage: "Outside WhatsApp conversation window"
      }
    end

    assert_response :ok
    assert_equal "failed", outbound.reload.status
    assert_equal "Outside WhatsApp conversation window", outbound.error_message
    assert_equal "undelivered", outbound.metadata.dig("provider", "status")
    assert_equal "failed", task.reload.message_delivery_summary
  end

  private

  def disable_ai_for(user)
    user.ai_setting.update!(
      confirm_sessions: false,
      send_pre_session_reminders: false,
      follow_up_no_response: false,
      ask_feedback_after_sessions: false,
      answer_basic_questions: false,
      escalate_important_conversations: false,
      payment_reminders: false
    )
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
