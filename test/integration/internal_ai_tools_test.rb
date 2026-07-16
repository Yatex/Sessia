require "test_helper"

class InternalAiToolsTest < ActionDispatch::IntegrationTest
  test "returns only signed tenant-scoped session evidence" do
    user = User.create!(name: "Tool Pro", email: "tools-#{SecureRandom.hex(3)}@example.com", password: "password123")
    client = user.clients.create!(name: "Scoped Client", phone: "+59899123456")
    session_record = user.sessions.create!(client: client, title: "Scoped Session", start_time: 1.day.from_now, end_time: 1.day.from_now + 1.hour)
    message = user.messages.create!(client: client, session: session_record, direction: "inbound", channel: "whatsapp", status: "sent", body: "What time?")
    task = user.ai_tasks.create!(client: client, session: session_record, trigger_event: "client_replied", automation_key: "answer_client_reply", scheduled_for: Time.current, context_data: { message_id: message.id })
    token = Ai::Grounded::ContextResolver.new(task: task).call.context_token

    with_env("SESSIA_AI_TOOL_SECRET" => "tool-secret") do
      post internal_ai_tool_path(tool_name: "session_context"), params: { context_token: token }, headers: { "X-Sessia-AI-Tool-Secret" => "tool-secret" }, as: :json
    end

    assert_response :success
    payload = response.parsed_body
    assert_equal "Scoped Session", payload.dig("result", "title")
    assert payload["evidence"].all? { |item| item["source_id"] == session_record.id.to_s }
    assert payload["duration_ms"].is_a?(Integer)
  end

  private

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
