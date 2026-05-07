require "test_helper"

class AvailabilityBlockerTest < ActiveSupport::TestCase
  test "blocking time cancels overlapping sessions and queues AI rebooking" do
    user = User.create!(name: "Blocking Pro", email: "blocking@example.com", password: "password123", time_zone: "America/Montevideo")
    client = user.clients.create!(name: "Client", phone: "+598 99 111 334")

    Time.use_zone(user.time_zone) do
      session_record = user.sessions.create!(
        client: client,
        title: "Therapy",
        start_time: Time.zone.parse("2026-05-04 10:00"),
        end_time: Time.zone.parse("2026-05-04 11:00"),
        confirmation_status: "confirmed"
      )

      assert_difference -> { user.schedule_blocks.count }, 1 do
        assert_difference -> { user.ai_tasks.where(trigger_event: "schedule_blocked").count }, 1 do
          result = Availability::Blocker.new(
            user: user,
            attributes: {
              title: "Unavailable",
              starts_at: Time.zone.parse("2026-05-04 09:30"),
              ends_at: Time.zone.parse("2026-05-04 10:30")
            }
          ).call

          assert_equal [session_record], result.affected_sessions
        end
      end

      assert session_record.reload.cancelled?
      assert session_record.confirmation_declined?
      task = user.ai_tasks.order(:created_at).last
      assert_equal "blocked_time_rebooking", task.automation_key
      assert_equal session_record, task.session
    end
  end
end
