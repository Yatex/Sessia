require "test_helper"

class AiGroundedV2Test < ActiveSupport::TestCase
  class StaticV2Client
    def initialize(decision) = @decision = decision
    def decide(_payload) = @decision.deep_dup
  end

  test "short confirmation uses requested pending interaction and conversation tools" do
    user, client, session_record, task = context("dale")
    decision = confirmation_decision(task, session_record)

    Ai::TaskProcessor.new(task: task, decision_client: StaticV2Client.new(decision)).call

    assert_equal "confirmed", session_record.reload.confirmation_status
    assert_equal %w[conversation_history pending_interaction session_context], task.ai_traces.last.tools_requested.sort
    assert_equal "accepted", task.reload.validation_status
  end

  test "confirmation is rejected when two sessions have pending requests" do
    user, client, session_record, task = context("yes")
    other = user.sessions.create!(client: client, title: "Other", start_time: 2.days.from_now, end_time: 2.days.from_now + 1.hour, confirmation_status: "pending")
    user.messages.create!(client: client, session: other, direction: "outbound", channel: "whatsapp", status: "sent", body: "Confirm other?", metadata: { automation_key: "confirm_session" })

    Ai::TaskProcessor.new(task: task, decision_client: StaticV2Client.new(confirmation_decision(task, session_record))).call

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

    Ai::TaskProcessor.new(task: task, decision_client: StaticV2Client.new(decision)).call

    assert_equal "accepted", task.reload.validation_status
    assert_equal ["session_context"], task.ai_traces.last.tools_completed
    assert_equal "test-model", task.ai_traces.last.model
  end

  test "before-session confirmation always uses grounded v2" do
    suffix = SecureRandom.hex(3)
    user = User.create!(name: "V2 Pro", email: "v2-before-#{suffix}@example.com", password: "password123")
    user.ai_setting.update!(confirm_sessions: true)
    client = user.clients.create!(name: "Client", phone: "+59899#{rand(10_000_000..99_999_999)}")
    session_record = user.sessions.create!(
      client: client,
      title: "Session",
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
    decision = {
      "action" => "send_message",
      "message_body" => "Can you confirm your session?",
      "confidence" => 0.98,
      "reasoning_summary" => "The upcoming session requires confirmation.",
      "evidence_ids" => ["session.#{session_record.id}.start_time"],
      "_trace" => { "tools_requested" => ["session_context"], "provider" => "vercel", "model" => "test-model" }
    }

    assert_difference -> { user.messages.outbound.count }, 1 do
      Ai::TaskProcessor.new(task: task, decision_client: StaticV2Client.new(decision)).call
    end

    assert_equal "completed", task.reload.status, task.result_data.inspect
    assert_equal "grounded_v2", task.result_data["architecture_version"]
    assert_equal "pending", session_record.reload.confirmation_status
    assert_equal "sessia_grounded_v2", task.ai_traces.last.prompt_version
    assert_equal ["session_context"], task.ai_traces.last.tools_completed
  end

  test "payment context remains read-only in grounded v2" do
    user, _client, session_record, task = context("Is this session paid?")
    session_record.update!(price_cents: 25_000, currency: "ARS", payment_status: "pending")
    context_token = Ai::Grounded::ContextResolver.new(task: task).call.context_token

    assert_no_changes -> { session_record.reload.payment_status } do
      response = Ai::Grounded::ToolRunner.new(
        context_token: context_token,
        tool_name: "payment_status"
      ).call

      assert_equal "pending", response.fetch(:result).fetch(:status)
      assert_equal 25_000, response.fetch(:result).fetch(:amount_cents)
      assert response.fetch(:evidence).any? { |item| item.fetch(:field) == "payment_status" }
    end
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

end
