require "test_helper"

class GoogleCalendarClientTest < ActiveSupport::TestCase
  test "builds authorization URL for offline Calendar access" do
    previous_client_id = ENV["GOOGLE_CLIENT_ID"]
    previous_client_secret = ENV["GOOGLE_CLIENT_SECRET"]
    ENV["GOOGLE_CLIENT_ID"] = "google-client-id"
    ENV["GOOGLE_CLIENT_SECRET"] = "google-client-secret"

    url = GoogleCalendar::Client.authorization_url(
      redirect_uri: "http://example.com/google-calendar/callback",
      state: "state-token"
    )
    uri = URI(url)
    query = Rack::Utils.parse_query(uri.query)

    assert_equal "accounts.google.com", uri.host
    assert_equal "offline", query["access_type"]
    assert_equal "consent", query["prompt"]
    assert_includes query["scope"], "https://www.googleapis.com/auth/calendar.events"
    assert_equal "state-token", query["state"]
  ensure
    ENV["GOOGLE_CLIENT_ID"] = previous_client_id
    ENV["GOOGLE_CLIENT_SECRET"] = previous_client_secret
  end
end
