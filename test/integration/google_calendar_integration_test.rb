require "test_helper"

class GoogleCalendarIntegrationTest < ActionDispatch::IntegrationTest
  test "settings exposes Google Calendar connection state" do
    user = User.create!(name: "Calendar Settings", email: "calendar-settings@example.com", password: "password123")

    post sign_in_url, params: { email: user.email, password: "password123" }
    get settings_url

    assert_response :success
    assert_match "Google Calendar", response.body
    assert_match "GOOGLE_CLIENT_ID", response.body
  end

  test "new sessions default to Google sync when connected and enabled" do
    user = User.create!(name: "Calendar Session", email: "calendar-session@example.com", password: "password123")
    user.clients.create!(name: "Calendar Client", email: "calendar-client@example.com", phone: "+598 99 123 321")
    connection = user.create_calendar_connection!(provider_account_email: "pro@example.com", sync_sessions: true)
    connection.access_token = "access-token"
    connection.refresh_token = "refresh-token"
    connection.save!

    post sign_in_url, params: { email: user.email, password: "password123" }
    get new_session_url

    assert_response :success
    assert_select "input[name='session[sync_to_google_calendar]'][type='checkbox']"
    assert_select "input[name='session[sync_to_google_calendar]'][checked='checked']"
  end
end
