require "test_helper"

class MessagingInboundWhatsappProcessorTest < ActiveSupport::TestCase
  class FakeAiProcessor
    class << self
      attr_accessor :messages
    end

    def initialize(message:)
      @message = message
    end

    def call
      self.class.messages ||= []
      self.class.messages << @message
    end
  end

  setup do
    FakeAiProcessor.messages = []
  end

  test "stores inbound whatsapp message and invokes AI processor" do
    user = User.create!(name: "WhatsApp Pro", email: "inbound-service@example.com", password: "password123")
    client = user.clients.create!(name: "Client", phone: "+598 99 111 222")
    session_record = user.sessions.create!(
      client: client,
      title: "Session",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour
    )

    result = Messaging::InboundWhatsappProcessor.new(
      params: {
        "From" => "whatsapp:+59899111222",
        "To" => "whatsapp:+14155238886",
        "Body" => "Can I ask something?",
        "MessageSid" => "SM-inbound-service-1"
      },
      ai_processor: FakeAiProcessor
    ).call

    assert result.accepted?
    assert_equal client, result.client
    assert_equal "Can I ask something?", result.message.body
    assert_equal session_record, result.message.session
    assert_equal [result.message], FakeAiProcessor.messages
  end

  test "does not duplicate twilio retry for the same message sid" do
    user = User.create!(name: "WhatsApp Pro", email: "inbound-dedupe@example.com", password: "password123")
    user.ai_setting.update!(answer_basic_questions: false, confirm_sessions: false, escalate_important_conversations: false)
    client = user.clients.create!(name: "Client", phone: "+598 99 111 223")
    params = {
      "From" => "whatsapp:+59899111223",
      "To" => "whatsapp:+14155238886",
      "Body" => "yes",
      "MessageSid" => "SM-dedupe-1"
    }

    assert_difference -> { user.messages.count }, 1 do
      2.times { Messaging::InboundWhatsappProcessor.new(params: params, ai_processor: FakeAiProcessor).call }
    end

    assert_equal 1, FakeAiProcessor.messages.size
    assert_equal client, user.messages.last.client
  end
end
