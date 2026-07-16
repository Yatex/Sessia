require "test_helper"

class AiPipelineV2Test < ActiveSupport::TestCase
  class CountingDecisionClient
    attr_reader :calls

    def initialize(decision)
      @decision = decision
      @calls = 0
      @mutex = Mutex.new
    end

    def decide(_payload)
      @mutex.synchronize { @calls += 1 }
      @decision
    end
  end

  class ConfigurationFailureProvider
    def configured? = true

    def deliver(**)
      raise Messaging::TwilioWhatsappProvider::DeliveryError.new(
        "The Content Variables parameter is invalid.",
        provider_metadata: { error_code: "21656", http_status: 400, error_message: "The Content Variables parameter is invalid." }
      )
    end
  end

  test "failed configuration does not allow the generator to recreate the same task" do
    user, _client, session_record = create_context("idempotent")
    user.ai_setting.update!(confirm_sessions: true)
    Ai::TaskGenerator.new(users: [user]).call
    task = user.ai_tasks.find_by!(session: session_record, automation_key: "confirm_session")
    task.update!(status: "failed", delivery_status: "failed_configuration", error_category: "provider_configuration")

    assert_no_difference -> { user.ai_tasks.count } do
      Ai::TaskGenerator.new(users: [user]).call
    end
    assert task.idempotency_key.present?
  end

  test "two workers claim one task and produce one decision" do
    user, client, session_record = create_context("claim")
    task = user.ai_tasks.create!(client: client, session: session_record, trigger_event: "before_session", automation_key: "confirm_session", scheduled_for: Time.current)
    client_stub = CountingDecisionClient.new(
      "action" => "do_nothing", "message_body" => nil, "note_body" => nil,
      "alert_body" => nil, "follow_up_at" => nil, "target_start_at" => nil,
      "confidence" => 0.9, "reasoning_summary" => "No action needed."
    )

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Ai::TaskProcessor.new(task: AiTask.find(task.id), decision_client: client_stub).call
        end
      end
    end
    threads.each(&:join)

    assert_equal 1, client_stub.calls
    assert_equal 1, task.ai_traces.count
  end

  test "a correct decision remains completed when Twilio has a configuration error" do
    user, client, session_record = create_context("delivery")
    task = user.ai_tasks.create!(client: client, session: session_record, trigger_event: "before_session", automation_key: "confirm_session", scheduled_for: Time.current)
    decision = {
      "action" => "send_message", "message_body" => "Can you confirm?", "note_body" => nil,
      "alert_body" => nil, "follow_up_at" => nil, "target_start_at" => nil,
      "confidence" => 0.98, "reasoning_summary" => "Ask for confirmation."
    }
    dispatcher = Messaging::Dispatcher.new(provider: ConfigurationFailureProvider.new)

    Ai::TaskProcessor.new(task: task, decision_client: CountingDecisionClient.new(decision), dispatcher: dispatcher).call
    task.reload

    assert_equal "completed", task.status
    assert_equal "completed", task.decision_status
    assert_equal "not_required", task.validation_status
    assert_equal "completed", task.execution_status
    assert_equal "failed_configuration", task.delivery_status
    assert_equal "provider_configuration", task.error_category
    assert_equal 1, task.delivery_attempts.count
    assert_equal 1, task.ai_alerts.count
    assert_equal 1, task.ai_traces.count
  end

  test "idempotency key changes for another scheduled window" do
    user, client, session_record = create_context("window")
    first = Ai::IdempotencyKey.for_task(user: user, client: client, session: session_record, automation_key: "confirm_session", trigger_event: "before_session", scheduled_window: "24h", channel: "whatsapp")
    second = Ai::IdempotencyKey.for_task(user: user, client: client, session: session_record, automation_key: "confirm_session", trigger_event: "before_session", scheduled_window: "48h", channel: "whatsapp")
    refute_equal first, second
  end

  private

  def create_context(suffix)
    user = User.create!(name: "Pipeline Pro", email: "pipeline-#{suffix}-#{SecureRandom.hex(3)}@example.com", password: "password123")
    client = user.clients.create!(name: "Client", phone: "+598 99 #{rand(100..999)} #{rand(100..999)}")
    session_record = user.sessions.create!(client: client, title: "Session", start_time: 1.day.from_now, end_time: 1.day.from_now + 1.hour)
    [user, client, session_record]
  end
end
