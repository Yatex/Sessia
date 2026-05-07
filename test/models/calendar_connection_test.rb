require "test_helper"

class CalendarConnectionTest < ActiveSupport::TestCase
  test "stores OAuth tokens encrypted" do
    user = User.create!(name: "Calendar Pro", email: "calendar-pro@example.com", password: "password123")
    connection = user.create_calendar_connection!

    connection.access_token = "access-token"
    connection.refresh_token = "refresh-token"
    connection.save!

    assert_equal "access-token", connection.reload.access_token
    assert_equal "refresh-token", connection.refresh_token
    assert_no_match "access-token", connection.access_token_ciphertext
    assert_no_match "refresh-token", connection.refresh_token_ciphertext
  end

  test "detects expiring access tokens" do
    user = User.create!(name: "Expiring Calendar Pro", email: "expiring-calendar@example.com", password: "password123")
    connection = user.create_calendar_connection!(access_token_expires_at: 1.minute.from_now)
    connection.access_token = "access-token"

    assert connection.access_token_expired?
  end
end
