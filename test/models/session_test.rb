require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "requires the client to belong to the same user" do
    owner = User.create!(name: "Owner", email: "owner@example.com", password: "password123")
    other_user = User.create!(name: "Other", email: "other@example.com", password: "password123")
    other_client = other_user.clients.create!(name: "Other Client", email: "client@example.com", phone: "+598 99 123 001")

    session_record = owner.sessions.new(
      client: other_client,
      title: "Private session",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 50.minutes
    )

    assert_not session_record.valid?
    assert_includes session_record.errors[:client], "must belong to your account"
  end

  test "requires end time after start time" do
    owner = User.create!(name: "Owner", email: "owner2@example.com", password: "password123")
    client = owner.clients.create!(name: "Client", email: "client2@example.com", phone: "+598 99 123 002")

    session_record = owner.sessions.new(
      client: client,
      title: "Time check",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now - 5.minutes
    )

    assert_not session_record.valid?
    assert_includes session_record.errors[:end_time], "must be after the start time"
  end

  test "stores session price in cents" do
    owner = User.create!(name: "Owner", email: "owner3@example.com", password: "password123")
    client = owner.clients.create!(name: "Client", email: "client3@example.com", phone: "+598 99 123 003")

    session_record = owner.sessions.create!(
      client: client,
      title: "Priced session",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 50.minutes,
      price: "85.50",
      currency: "usd"
    )

    assert_equal 8550, session_record.price_cents
    assert_equal "USD", session_record.currency
    assert_equal 85.5, session_record.price
  end

  test "generates weekly recurring sessions on selected days" do
    owner = User.create!(name: "Owner", email: "owner4@example.com", password: "password123", time_zone: "America/Montevideo")
    client = owner.clients.create!(name: "Client", email: "client4@example.com", phone: "+598 99 123 004")
    start_time = Time.zone.parse("2026-05-05 09:00")

    session_record = owner.sessions.create!(
      client: client,
      title: "Weekly practice",
      start_time: start_time,
      end_time: start_time + 50.minutes,
      recurring: true,
      recurrence_frequency: "weekly",
      recurrence_days: [2, 4],
      recurrence_ends_on: Date.parse("2026-05-14")
    )

    assert_difference -> { owner.sessions.where(parent_session: session_record).count }, 3 do
      RecurringSessionGenerator.new(session_record).generate!
    end

    generated_dates = owner.sessions.where(parent_session: session_record).order(:start_time).map { |generated| generated.start_time.to_date }
    assert_equal [Date.parse("2026-05-07"), Date.parse("2026-05-12"), Date.parse("2026-05-14")], generated_dates
  end
end
