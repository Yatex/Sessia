require "test_helper"

class PublicLandingTest < ActionDispatch::IntegrationTest
  test "guests see the Sessia landing page before auth" do
    get root_url

    assert_response :success
    assert_select "h1", "Sessia"
    assert_match "Run your client sessions", response.body
    assert_select "a[href=?]", sign_up_path, minimum: 1
    assert_select "a[href=?]", sign_in_path, minimum: 1
  end

  test "authenticated users are redirected from landing to dashboard" do
    user = User.create!(
      name: "Landing Redirect",
      email: "landing-redirect@example.com",
      password: "password123",
      password_confirmation: "password123",
      time_zone: "America/Montevideo"
    )

    post sign_in_url, params: { email: user.email, password: "password123" }
    get root_url

    assert_redirected_to dashboard_url
  end
end
