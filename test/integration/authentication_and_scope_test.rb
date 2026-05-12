require "test_helper"

class AuthenticationAndScopeTest < ActionDispatch::IntegrationTest
  test "user can sign up and reach the dashboard" do
    post sign_up_url, params: {
      user: {
        name: "New Pro",
        email: "newpro@example.com",
        password: "password123",
        password_confirmation: "password123",
        time_zone: "America/Montevideo"
      }
    }

    assert_redirected_to dashboard_url
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /-/
    assert_equal "trial", User.find_by!(email: "newpro@example.com").current_subscription.plan_tier
  end

  test "dashboard is authenticated and scoped to current user" do
    session_start = Time.current.beginning_of_week(:monday) + 9.hours
    user = User.create!(name: "Scoped Pro", email: "scoped@example.com", password: "password123")
    client = user.clients.create!(name: "Visible Client", email: "visible@example.com", phone: "+598 99 123 003")
    user.sessions.create!(
      client: client,
      title: "Visible Session",
      start_time: session_start,
      end_time: session_start + 50.minutes
    )

    other_user = User.create!(name: "Other Pro", email: "otherpro@example.com", password: "password123")
    other_client = other_user.clients.create!(name: "Hidden Client", email: "hidden@example.com", phone: "+598 99 123 004")
    other_user.sessions.create!(
      client: other_client,
      title: "Hidden Session",
      start_time: session_start + 1.hour,
      end_time: session_start + 1.hour + 50.minutes
    )

    get dashboard_url
    assert_redirected_to sign_in_url

    post sign_in_url, params: { email: "scoped@example.com", password: "password123" }
    follow_redirect!

    assert_response :success
    assert_match "Visible Client", response.body
    assert_no_match "Hidden Client", response.body
  end
end
