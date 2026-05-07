require "test_helper"

class AvailabilityCalendarTest < ActiveSupport::TestCase
  test "offers working-hour slots and excludes breaks, blocks, and occupied sessions" do
    user = User.create!(name: "Available Pro", email: "available@example.com", password: "password123", time_zone: "America/Montevideo")
    client = user.clients.create!(name: "Client", phone: "+598 99 111 333")

    Time.use_zone(user.time_zone) do
      user.sessions.create!(
        client: client,
        title: "Booked",
        start_time: Time.zone.parse("2026-05-04 09:00"),
        end_time: Time.zone.parse("2026-05-04 10:00")
      )
      user.schedule_blocks.create!(
        title: "Admin",
        starts_at: Time.zone.parse("2026-05-04 15:00"),
        ends_at: Time.zone.parse("2026-05-04 16:00")
      )

      calendar = Availability::Calendar.new(user)

      assert calendar.available?(Time.zone.parse("2026-05-04 10:00"), duration_minutes: 60)
      assert_not calendar.available?(Time.zone.parse("2026-05-04 09:00"), duration_minutes: 60)
      assert_not calendar.available?(Time.zone.parse("2026-05-04 18:00"), duration_minutes: 60)
      assert_not calendar.available?(Time.zone.parse("2026-05-04 15:00"), duration_minutes: 60)
      assert_not calendar.available?(Time.zone.parse("2026-05-03 10:00"), duration_minutes: 60)
    end
  end
end
