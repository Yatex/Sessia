require "test_helper"

class ClientPortalTest < ActionDispatch::IntegrationTest
  test "client link marks client as linked" do
    user = User.create!(name: "Professional", email: "portal-pro@example.com", password: "password123")
    client = user.clients.create!(name: "Portal Client", phone: "+598 99 123 005")

    assert_changes -> { client.reload.linked? }, from: false, to: true do
      get client_portal_url(client.portal_token)
    end

    assert_response :success
    assert_match "Portal Client", response.body
  end

  test "client link uses the public portal layout even when professional is signed in" do
    user = User.create!(name: "Professional", email: "portal-layout@example.com", password: "password123")
    client = user.clients.create!(name: "Portal Client", phone: "+598 99 123 007")

    post sign_in_url, params: { email: user.email, password: "password123" }
    get client_portal_url(client.portal_token)

    assert_response :success
    assert_match 'class="public-body"', response.body
    assert_no_match 'class="app-shell"', response.body
    assert_no_match "Sign out", response.body
  end

  test "linked client can send a schedule change request" do
    user = User.create!(name: "Professional", email: "portal-pro-2@example.com", password: "password123")
    client = user.clients.create!(name: "Portal Client", phone: "+598 99 123 006")
    session_record = user.sessions.create!(
      client: client,
      title: "Check-in",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 50.minutes
    )

    assert_difference -> { client.messages.count }, 1 do
      post client_portal_messages_url(client.portal_token), params: {
        message: {
          subject: "Schedule change request",
          session_id: session_record.id,
          body: "Can we move this session to the afternoon?"
        }
      }
    end

    message = client.messages.last
    assert_redirected_to client_portal_url(client.portal_token)
    assert_equal "inbound", message.direction
    assert_equal "whatsapp", message.channel
    assert_equal user, message.user
    assert_equal session_record, message.session
  end
end
