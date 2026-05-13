require "test_helper"

class AiDeliveryWindowTest < ActiveSupport::TestCase
  test "blocks proactive work outside calm delivery hours" do
    user = User.create!(name: "Window Pro", email: "ai-window@example.com", password: "password123", time_zone: "America/Montevideo")
    client = user.clients.create!(name: "Window Client", phone: "+598 99 111 240")
    session = user.sessions.create!(
      client: client,
      title: "Coaching",
      start_time: Time.zone.parse("2026-05-13 15:00:00 UTC"),
      end_time: Time.zone.parse("2026-05-13 16:00:00 UTC")
    )
    task = user.ai_tasks.create!(
      client: client,
      session: session,
      trigger_event: "before_session",
      automation_key: "confirm_session",
      scheduled_for: Time.current
    )

    assert_not Ai::DeliveryWindow.allows?(task: task, reference_time: Time.zone.parse("2026-05-13 05:00:00 UTC"))
    assert Ai::DeliveryWindow.allows?(task: task, reference_time: Time.zone.parse("2026-05-13 14:00:00 UTC"))
  end

  test "allows client replies and urgent upcoming session tasks outside delivery hours" do
    user = User.create!(name: "Urgent Pro", email: "ai-window-urgent@example.com", password: "password123", time_zone: "America/Montevideo")
    client = user.clients.create!(name: "Urgent Client", phone: "+598 99 111 241")
    reference_time = Time.zone.parse("2026-05-13 05:00:00 UTC")
    session = user.sessions.create!(
      client: client,
      title: "Early session",
      start_time: reference_time + 2.hours,
      end_time: reference_time + 3.hours
    )
    proactive_task = user.ai_tasks.create!(
      client: client,
      session: session,
      trigger_event: "before_session",
      automation_key: "send_pre_session_reminder",
      scheduled_for: reference_time
    )
    reply_task = user.ai_tasks.create!(
      client: client,
      session: session,
      trigger_event: "client_replied",
      automation_key: "answer_client_reply",
      scheduled_for: reference_time
    )

    assert Ai::DeliveryWindow.allows?(task: proactive_task, reference_time: reference_time)
    assert Ai::DeliveryWindow.allows?(task: reply_task, reference_time: reference_time)
  end
end
