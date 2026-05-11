require "test_helper"

class GoogleAuthTest < ActionDispatch::IntegrationTest
  test "google auth creates and signs in a new user" do
    with_google_auth_stubs(
      "id" => "google-uid-1",
      "email" => "google-new@example.com",
      "verified_email" => true,
      "name" => "Google New",
      "picture" => "https://example.com/avatar.png"
    ) do |state|
      get google_auth_url, params: { origin: "sign_up", time_zone: "America/Montevideo" }
      assert_response :redirect

      get google_auth_callback_url, params: { code: "oauth-code", state: state.call }
    end

    assert_redirected_to dashboard_url
    user = User.find_by_normalized_email("google-new@example.com")
    assert user
    assert_equal "google-uid-1", user.google_uid
    assert_equal "America/Montevideo", user.time_zone
  end

  test "google auth links and signs in an existing user by verified email" do
    user = User.create!(
      name: "Existing User",
      email: "existing-google@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    with_google_auth_stubs(
      "id" => "google-existing-uid",
      "email" => user.email,
      "verified_email" => true,
      "name" => "Existing User"
    ) do |state|
      get google_auth_url, params: { origin: "sign_in" }
      get google_auth_callback_url, params: { code: "oauth-code", state: state.call }
    end

    assert_redirected_to dashboard_url
    assert_equal "google-existing-uid", user.reload.google_uid
  end

  test "google auth rejects invalid oauth state" do
    with_google_auth_stubs(
      "id" => "google-invalid-state",
      "email" => "invalid-state@example.com",
      "verified_email" => true
    ) do
      get google_auth_url, params: { origin: "sign_in" }
      get google_auth_callback_url, params: { code: "oauth-code", state: "bad-state" }
    end

    assert_redirected_to sign_in_url
    assert_nil User.find_by_normalized_email("invalid-state@example.com")
  end

  private

  def with_google_auth_stubs(profile)
    previous_env = {
      "GOOGLE_CLIENT_ID" => ENV["GOOGLE_CLIENT_ID"],
      "GOOGLE_CLIENT_SECRET" => ENV["GOOGLE_CLIENT_SECRET"]
    }
    ENV["GOOGLE_CLIENT_ID"] = "google-client-id"
    ENV["GOOGLE_CLIENT_SECRET"] = "google-client-secret"

    captured_state = nil
    singleton = class << GoogleAuth::Client; self; end
    original_authorization_url = GoogleAuth::Client.method(:authorization_url)
    original_exchange_code = GoogleAuth::Client.method(:exchange_code)
    original_userinfo = GoogleAuth::Client.method(:userinfo)

    singleton.define_method(:authorization_url) do |redirect_uri:, state:|
      captured_state = state
      "https://accounts.google.com/o/oauth2/v2/auth?state=#{state}&redirect_uri=#{CGI.escape(redirect_uri)}"
    end
    singleton.define_method(:exchange_code) do |code:, redirect_uri:|
      { "access_token" => "access-token", "expires_in" => 3600 }
    end
    singleton.define_method(:userinfo) do |access_token:|
      profile
    end

    yield -> { captured_state }
  ensure
    singleton&.define_method(:authorization_url) { |redirect_uri:, state:| original_authorization_url.call(redirect_uri: redirect_uri, state: state) }
    singleton&.define_method(:exchange_code) { |code:, redirect_uri:| original_exchange_code.call(code: code, redirect_uri: redirect_uri) }
    singleton&.define_method(:userinfo) { |access_token:| original_userinfo.call(access_token: access_token) }
    previous_env&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
