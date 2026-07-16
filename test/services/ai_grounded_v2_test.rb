require "test_helper"

class AiGroundedV2Test < ActiveSupport::TestCase
  class StaticV2Client
    def initialize(decision) = @decision = decision
    def decide(_payload) = @decision.deep_dup
  end

  test "short confirmation uses requested pending interaction and conversation tools" do
    user, client, session_record, task = context("dale")
    decision = confirmation_decision(task, session_record)

    with_v2 { Ai::TaskProcessor.new(task: task, decision_client: StaticV2Client.new(decision)).call }

    assert_equal "confirmed", session_record.reload.confirmation_status
    assert_equal %w[conversation_history pending_interaction session_context], task.ai_traces.last.tools_requested.sort
    assert_equal "accepted", task.reload.validation_status
  end

  test "confirmation is rejected when two sessions have pending requests" do
    user, client, session_record, task = context("yes")
    other = user.sessions.create!(client: client, title: "Other", start_time: 2.days.from_now, end_time: 2.days.from_now + 1.hour, confirmation_status: "pending")
    user.messages.create!(client: client, session: other, direction: "outbound", channel: "whatsapp", status: "sent", body: "Confirm other?", metadata: { automation_key: "confirm_session" })

    with_v2 { Ai::TaskProcessor.new(task: task, decision_client: StaticV2Client.new(confirmation_decision(task, session_record))).call }

    assert_equal "pending", session_record.reload.confirmation_status
    assert_equal "rejected", task.reload.validation_status
    assert_includes task.result_data.dig("validation", "errors"), "ambiguous_confirmation_context"
  end

  test "session time answer requires and records session_context" do
    user, _client, session_record, task = context("A que hora es?")
    decision = {
      "action" => "send_message", "message_body" => "Tu sesion es manana.",
      "confidence" => 0.95, "reasoning_summary" => "Answered from session context.",
      "evidence_ids" => ["session.#{session_record.id}.start_time"],
      "_trace" => { "tools_requested" => ["session_context"], "provider" => "vercel", "model" => "test-model" }
    }

    with_v2 { Ai::TaskProcessor.new(task: task, decision_client: StaticV2Client.new(decision)).call }

    assert_equal "accepted", task.reload.validation_status
    assert_equal ["session_context"], task.ai_traces.last.tools_completed
    assert_equal "test-model", task.ai_traces.last.model
  end

  private

  def context(body)
    suffix = SecureRandom.hex(3)
    user = User.create!(name: "V2 Pro", email: "v2-#{suffix}@example.com", password: "password123")
    user.ai_setting.update!(confirm_sessions: true, answer_basic_questions: true)
    client = user.clients.create!(name: "Client", phone: "+59899#{rand(10_000_000..99_999_999)}")
    session_record = user.sessions.create!(client: client, title: "Session", start_time: 1.day.from_now, end_time: 1.day.from_now + 1.hour, confirmation_status: "pending")
    user.messages.create!(client: client, session: session_record, direction: "outbound", channel: "whatsapp", status: "sent", body: "Can you confirm?", metadata: { automation_key: "confirm_session" })
    inbound = user.messages.create!(client: client, session: session_record, direction: "inbound", channel: "whatsapp", status: "sent", body: body)
    task = user.ai_tasks.create!(client: client, session: session_record, trigger_event: "client_replied", automation_key: "answer_client_reply", scheduled_for: Time.current, context_data: { message_id: inbound.id })
    [user, client, session_record, task]
  end

  def confirmation_decision(_task, session_record)
    {
      "action" => "mark_session_confirmed", "confidence" => 0.97,
      "reasoning_summary" => "The reply confirms the single pending interaction.",
      "evidence_ids" => ["message.#{session_record.messages.inbound.last.id}.body", "session.#{session_record.id}.confirmation_status"],
      "_trace" => { "tools_requested" => %w[pending_interaction conversation_history session_context], "provider" => "vercel", "model" => "test-model" }
    }
  end

  def with_v2
    previous = ENV["SESSIA_GROUNDED_INBOUND_V2"]
    ENV["SESSIA_GROUNDED_INBOUND_V2"] = "true"
    yield
  ensure
    previous.nil? ? ENV.delete("SESSIA_GROUNDED_INBOUND_V2") : ENV["SESSIA_GROUNDED_INBOUND_V2"] = previous
  end
end
