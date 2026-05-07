require "test_helper"

class AiTaskGeneratorTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "creates confirmation and payment tasks for enabled assistant settings" do
    travel_to Time.zone.local(2026, 5, 5, 10, 0, 0) do
      user = User.create!(name: "AI Pro", email: "ai-generator@example.com", password: "password123")
      user.ai_setting.update!(confirm_sessions: true, payment_reminders: true)
      client = user.clients.create!(name: "Client", phone: "+598 99 111 222")
      session_record = user.sessions.create!(
        client: client,
        title: "Coaching",
        start_time: 1.day.from_now,
        end_time: 1.day.from_now + 1.hour,
        confirmation_status: "not_requested",
        payment_status: "pending",
        price_cents: 8000
      )

      tasks = Ai::TaskGenerator.new(users: [user]).call

      assert_equal 2, tasks.size
      assert user.ai_tasks.exists?(session: session_record, automation_key: "confirm_session")
      assert user.ai_tasks.exists?(session: session_record, automation_key: "payment_reminder")

      assert_no_difference -> { user.ai_tasks.count } do
        Ai::TaskGenerator.new(users: [user]).call
      end
    end
  end

  test "does not create disabled tasks" do
    user = User.create!(name: "AI Pro", email: "ai-disabled@example.com", password: "password123")
    user.ai_setting.update!(confirm_sessions: false, payment_reminders: false)
    client = user.clients.create!(name: "Client", phone: "+598 99 111 223")
    user.sessions.create!(
      client: client,
      title: "Consulting",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      confirmation_status: "not_requested",
      payment_status: "pending",
      price_cents: 9000
    )

    assert_no_difference -> { user.ai_tasks.count } do
      Ai::TaskGenerator.new(users: [user]).call
    end
  end
end
