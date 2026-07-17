require "test_helper"

class AiGroundedTaskProcessorTest < ActiveSupport::TestCase
  class PayloadDecisionClient
    attr_reader :payload

    def initialize(&decision_builder)
      @decision_builder = decision_builder
    end

    def decide(payload)
      @payload = payload
      @decision_builder.call(payload)
    end
  end

  test "grounded inbound confirmation validates evidence before changing the session" do
    user, client, session_record, task = confirmation_context("yes")
    decision_client = PayloadDecisionClient.new do |payload|
      {
        "action" => "mark_session_confirmed",
        "confidence" => 0.99,
        "reasoning_summary" => "The client explicitly confirmed the single referenced session.",
        "evidence_ids" => [
          payload.fetch(:recent_messages).last.fetch("evidence_id"),
          evidence_id(payload, "session", "confirmation_status")
        ]
      }
    end

    with_grounded_inbound do
      assert_difference -> { user.messages.outbound.count }, 1 do
        Ai::TaskProcessor.new(task: task, decision_client: decision_client).call
      end
    end

    assert_equal "confirmed", session_record.reload.confirmation_status
    assert_equal "completed", task.reload.status
    assert_equal "grounded_v1", task.result_data["architecture_version"]
    assert_equal true, task.result_data.dig("validation", "valid")
    assert_equal %w[client_context session_context conversation_history professional_settings availability_options payment_status workspace_policies], task.result_data["tools_executed"]
    assert decision_client.payload.fetch(:context_token).present?
  end

  test "rejects confirmation without a grounded confirmation request" do
    user, _client, session_record, task = confirmation_context("yes", confirmation_request: false)
    decision_client = PayloadDecisionClient.new do |payload|
      {
        "action" => "mark_session_confirmed",
        "confidence" => 0.99,
        "reasoning_summary" => "Candidate confirmation.",
        "evidence_ids" => [
          payload.fetch(:recent_messages).last.fetch("evidence_id"),
          evidence_id(payload, "session", "confirmation_status")
        ]
      }
    end

    with_grounded_inbound do
      assert_no_difference -> { user.messages.outbound.count } do
        Ai::TaskProcessor.new(task: task, decision_client: decision_client).call
      end
    end

    assert_equal "pending", session_record.reload.confirmation_status
    assert_equal "skipped", task.reload.status
    assert_includes task.result_data.dig("validation", "errors"), "ambiguous_confirmation_context"
    assert_equal false, task.result_data.dig("effect_execution", "performed")
  end

  test "rejects evidence that is not part of the resolved tenant context" do
    user, _client, session_record, task = confirmation_context("yes")
    other_user = User.create!(name: "Other", email: "other-grounded@example.com", password: "password123")
    other_client = other_user.clients.create!(name: "Other client", phone: "+598 99 777 100")
    other_message = other_user.messages.create!(client: other_client, direction: :inbound, channel: "whatsapp", status: :sent, body: "yes")
    decision_client = PayloadDecisionClient.new do |payload|
      {
        "action" => "mark_session_confirmed",
        "confidence" => 0.99,
        "reasoning_summary" => "Uses foreign evidence.",
        "evidence_ids" => ["message.#{other_message.id}.body", evidence_id(payload, "session", "confirmation_status")]
      }
    end

    with_grounded_inbound { Ai::TaskProcessor.new(task: task, decision_client: decision_client).call }

    assert_equal "pending", session_record.reload.confirmation_status
    assert_equal "skipped", task.reload.status
    assert task.result_data.dig("validation", "errors").any? { |error| error.start_with?("unknown_evidence:") }
  end

  test "rejects low confidence effects without sending or mutating" do
    user, _client, session_record, task = confirmation_context("maybe")
    decision_client = PayloadDecisionClient.new do |payload|
      {
        "action" => "mark_session_confirmed",
        "confidence" => 0.51,
        "reasoning_summary" => "Uncertain candidate.",
        "evidence_ids" => [payload.fetch(:recent_messages).last.fetch("evidence_id"), evidence_id(payload, "session", "confirmation_status")]
      }
    end

    with_grounded_inbound do
      assert_no_difference -> { user.messages.outbound.count } do
        Ai::TaskProcessor.new(task: task, decision_client: decision_client).call
      end
    end

    assert_equal "pending", session_record.reload.confirmation_status
    assert_includes task.reload.result_data.dig("validation", "errors"), "confidence_below_threshold"
  end

  test "environment variables cannot disable grounded v2" do
    _user, _client, _session_record, task = confirmation_context("yes")

    with_env(
      "SESSIA_AI_GROUNDED_INBOUND_ENABLED" => "false",
      "SESSIA_GROUNDED_INBOUND_V2" => "false",
      "SESSIA_GROUNDED_BEFORE_SESSION_V2" => "false"
    ) do
      assert Ai::Grounded::Feature.grounded_for?(task)
      assert Ai::Grounded::Feature.v2_for?(task)
    end
  end

  test "rejects a model supplied session id outside the signed context" do
    _user, _client, session_record, task = confirmation_context("yes")
    other_user = User.create!(name: "Other owner", email: "other-session-grounded@example.com", password: "password123")
    other_client = other_user.clients.create!(name: "Other client", phone: "+598 99 777 101")
    other_session = other_user.sessions.create!(client: other_client, title: "Other", start_time: 2.days.from_now, end_time: 2.days.from_now + 1.hour)
    decision_client = PayloadDecisionClient.new do |payload|
      {
        "action" => "mark_session_confirmed",
        "session_id" => other_session.id,
        "confidence" => 0.99,
        "reasoning_summary" => "Attempts to target a foreign session.",
        "evidence_ids" => [payload.fetch(:recent_messages).last.fetch("evidence_id"), evidence_id(payload, "session", "confirmation_status")]
      }
    end

    with_grounded_inbound { Ai::TaskProcessor.new(task: task, decision_client: decision_client).call }

    assert_equal "pending", session_record.reload.confirmation_status
    assert_includes task.reload.result_data.dig("validation", "errors"), "unauthorized_session"
  end

  test "rechecks availability when a slot becomes occupied before execution" do
    user, client, session_record, task = confirmation_context("move my session")
    original_start = session_record.start_time
    decision_client = PayloadDecisionClient.new do |payload|
      slot = payload.fetch(:availability_options).first
      user.sessions.create!(
        client: client,
        title: "Concurrent booking",
        start_time: Time.iso8601(slot.fetch("starts_at")),
        end_time: Time.iso8601(slot.fetch("ends_at"))
      )
      {
        "action" => "reschedule_session",
        "target_start_at" => slot.fetch("starts_at"),
        "confidence" => 0.98,
        "reasoning_summary" => "Client selected an offered slot.",
        "evidence_ids" => [payload.fetch(:recent_messages).last.fetch("evidence_id"), slot.fetch("evidence_id")]
      }
    end

    with_grounded_inbound do
      assert_no_difference -> { user.messages.outbound.count } do
        Ai::TaskProcessor.new(task: task, decision_client: decision_client).call
      end
    end

    assert_equal original_start.to_i, session_record.reload.start_time.to_i
    assert_equal "failed", task.reload.status
    assert_match "no longer available", task.result_data.dig("effect_execution", "error_message")
  end

  private

  def confirmation_context(body, confirmation_request: true)
    suffix = SecureRandom.hex(4)
    user = User.create!(name: "Grounded Pro", email: "grounded-#{suffix}@example.com", password: "password123")
    user.ai_setting.update!(confirm_sessions: true, answer_basic_questions: true)
    client = user.clients.create!(name: "Client", phone: "+598 99 #{rand(100..999)} #{rand(100..999)}")
    session_record = user.sessions.create!(
      client: client,
      title: "Session",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      confirmation_status: :pending
    )
    if confirmation_request
      user.messages.create!(
        client: client,
        session: session_record,
        direction: :outbound,
        channel: "whatsapp",
        status: :sent,
        body: "Can you confirm your session?",
        metadata: { "source" => "ai", "automation_key" => "confirm_session" }
      )
    end
    inbound = user.messages.create!(
      client: client,
      session: session_record,
      direction: :inbound,
      channel: "whatsapp",
      status: :sent,
      body: body
    )
    task = user.ai_tasks.create!(
      client: client,
      session: session_record,
      trigger_event: "client_replied",
      automation_key: "answer_client_reply",
      scheduled_for: Time.current,
      context_data: { "message_id" => inbound.id }
    )
    [user, client, session_record, task]
  end

  def evidence_id(payload, source_type, field)
    payload.fetch(:evidence).find { |item| item["source_type"] == source_type && item["field"] == field }.fetch("evidence_id")
  end

  def with_grounded_inbound(&block)
    singleton = Ai::Grounded::Feature.singleton_class
    original = singleton.instance_method(:v2_for?)
    singleton.define_method(:v2_for?) { |_task| false }
    block.call
  ensure
    singleton.define_method(:v2_for?, original)
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
