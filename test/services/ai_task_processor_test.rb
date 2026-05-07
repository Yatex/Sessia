require "test_helper"

class AiTaskProcessorTest < ActiveSupport::TestCase
  class StaticDecisionClient
    attr_reader :payload

    def initialize(decision)
      @decision = decision
    end

    def decide(payload)
      @payload = payload
      @decision
    end
  end

  test "sends decision payload to AI service and executes message action" do
    user = User.create!(name: "AI Pro", email: "ai-processor@example.com", password: "password123")
    user.ai_setting.update!(confirm_sessions: true)
    client = user.clients.create!(name: "Client", phone: "+598 99 111 224")
    session_record = user.sessions.create!(
      client: client,
      title: "Therapy",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      confirmation_status: "not_requested"
    )
    task = user.ai_tasks.create!(
      client: client,
      session: session_record,
      trigger_event: "before_session",
      automation_key: "confirm_session",
      scheduled_for: Time.current
    )
    client_stub = StaticDecisionClient.new(
      "action" => "send_message",
      "message_body" => "Can you confirm?",
      "note_body" => nil,
      "alert_body" => nil,
      "follow_up_at" => nil,
      "confidence" => 0.98,
      "reasoning_summary" => "Test decision"
    )

    assert_difference -> { user.messages.outbound.count }, 1 do
      Ai::TaskProcessor.new(task: task, decision_client: client_stub).call
    end

    assert_equal "completed", task.reload.status
    assert_equal "pending", session_record.reload.confirmation_status
    assert_equal "confirm_session", client_stub.payload.fetch(:instruction).fetch(:key)
    assert_equal "Can you confirm?", user.messages.last.body
    assert_equal "queued", user.messages.last.status
  end

  test "client reply can mark session confirmed and send acknowledgement" do
    user = User.create!(name: "AI Pro", email: "ai-reply@example.com", password: "password123")
    user.ai_setting.update!(confirm_sessions: true, answer_basic_questions: true)
    client = user.clients.create!(name: "Client", phone: "+598 99 111 225")
    session_record = user.sessions.create!(
      client: client,
      title: "Tutoring",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      confirmation_status: "pending"
    )
    inbound = user.messages.create!(
      client: client,
      session: session_record,
      direction: "inbound",
      channel: "whatsapp",
      status: "sent",
      body: "yes",
      sent_at: Time.current
    )
    task = user.ai_tasks.create!(
      client: client,
      session: session_record,
      trigger_event: "client_replied",
      automation_key: "answer_client_reply",
      scheduled_for: Time.current,
      context_data: { "message_id" => inbound.id }
    )
    client_stub = StaticDecisionClient.new(
      "action" => "mark_session_confirmed",
      "message_body" => nil,
      "note_body" => nil,
      "alert_body" => nil,
      "follow_up_at" => nil,
      "confidence" => 0.99,
      "reasoning_summary" => "Client confirmed"
    )

    assert_difference -> { user.messages.outbound.count }, 1 do
      Ai::TaskProcessor.new(task: task, decision_client: client_stub).call
    end

    assert_equal "confirmed", session_record.reload.confirmation_status
    assert_equal "completed", task.reload.status
    assert_match "confirmed", user.messages.last.body
  end

  test "client reply can reschedule a session into an available slot" do
    user = User.create!(name: "AI Pro", email: "ai-reschedule@example.com", password: "password123", time_zone: "America/Montevideo")
    user.ai_setting.update!(answer_basic_questions: true)
    client = user.clients.create!(name: "Client", phone: "+598 99 111 226")

    Time.use_zone(user.time_zone) do
      target_date = Date.current + 1.day
      target_date += 1.day until target_date.monday?
      target_start = Time.zone.local(target_date.year, target_date.month, target_date.day, 10, 0)

      session_record = user.sessions.create!(
        client: client,
        title: "Tutoring",
        start_time: target_start + 1.day,
        end_time: target_start + 1.day + 1.hour,
        confirmation_status: "pending"
      )
      inbound = user.messages.create!(
        client: client,
        session: session_record,
        direction: "inbound",
        channel: "whatsapp",
        status: "sent",
        body: "option 1",
        sent_at: Time.current
      )
      task = user.ai_tasks.create!(
        client: client,
        session: session_record,
        trigger_event: "client_replied",
        automation_key: "answer_client_reply",
        scheduled_for: Time.current,
        context_data: { "message_id" => inbound.id }
      )
      client_stub = StaticDecisionClient.new(
        "action" => "reschedule_session",
        "message_body" => nil,
        "note_body" => nil,
        "alert_body" => nil,
        "follow_up_at" => nil,
        "target_start_at" => target_start.iso8601,
        "confidence" => 0.96,
        "reasoning_summary" => "Client selected an available slot"
      )

      assert_difference -> { user.messages.outbound.count }, 1 do
        Ai::TaskProcessor.new(task: task, decision_client: client_stub).call
      end

      assert_equal target_start.to_i, session_record.reload.start_time.to_i
      assert_equal "scheduled", session_record.status
      assert_equal "pending", session_record.confirmation_status
      assert_equal "completed", task.reload.status
      assert_match "moved", user.messages.last.body
      assert client_stub.payload.fetch(:availability_options).any?
    end
  end
end
