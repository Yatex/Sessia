require "test_helper"

class FiltersAndSettingsTest < ActionDispatch::IntegrationTest
  test "session, client, and payment filters scope visible records" do
    user = User.create!(name: "Filter Pro", email: "filter@example.com", password: "password123")
    ana = user.clients.create!(name: "Ana Filter", email: "ana-filter@example.com", phone: "+598 99 111 111")
    lucas = user.clients.create!(name: "Lucas Filter", email: "lucas-filter@example.com", phone: "+598 99 222 222", linked_at: Time.current)

    paid_session = user.sessions.create!(
      client: ana,
      title: "Paid therapy",
      start_time: Time.zone.parse("2026-05-05 09:00"),
      end_time: Time.zone.parse("2026-05-05 10:00"),
      confirmation_status: "confirmed",
      payment_status: "paid"
    )
    user.sessions.create!(
      client: lucas,
      title: "Unpaid tutoring",
      start_time: Time.zone.parse("2026-05-06 09:00"),
      end_time: Time.zone.parse("2026-05-06 10:00"),
      confirmation_status: "pending",
      payment_status: "pending"
    )
    user.payment_records.create!(client: ana, session: paid_session, amount_cents: 10_000, currency: "USD", status: "paid", due_on: Date.new(2026, 5, 5))

    post sign_in_url, params: { email: user.email, password: "password123" }

    get clients_url, params: { query: "Lucas", linked: "linked" }
    assert_response :success
    assert_match "Lucas Filter", response.body
    assert_no_match "Ana Filter", response.body

    get sessions_url, params: { client_id: ana.id, payment_status: "paid" }
    assert_response :success
    assert_match "Paid therapy", response.body
    assert_no_match "Unpaid tutoring", response.body

    get payments_url, params: { client_id: ana.id, payment_status: "paid" }
    assert_response :success
    assert_match "Paid therapy", response.body
    assert_no_match "Unpaid tutoring", response.body
  end

  test "settings separates profile language from password reset" do
    user = User.create!(name: "Settings Pro", email: "settings@example.com", password: "password123")
    post sign_in_url, params: { email: user.email, password: "password123" }

    patch settings_url, params: {
      user: {
        name: "Settings Pro Updated",
        email: user.email,
        locale: "es",
        time_zone: "America/Montevideo",
        payment_instructions: "Transferencia bancaria o Mercado Pago alias sessia.pro"
      }
    }

    assert_redirected_to settings_url
    user.reload
    assert_equal "Settings Pro Updated", user.name
    assert_equal "es", user.locale
    assert_equal "Transferencia bancaria o Mercado Pago alias sessia.pro", user.payment_instructions
    assert_nil user.password_reset_token_digest

    post password_reset_settings_url
    assert_redirected_to settings_url
    assert user.reload.password_reset_token_digest.present?

    get settings_url
    assert_response :success
    assert_match "Configuración", response.body
  end

  test "settings saves working hours from interactive availability cells" do
    user = User.create!(name: "Grid Pro", email: "grid-settings@example.com", password: "password123")
    post sign_in_url, params: { email: user.email, password: "password123" }

    patch availability_settings_url, params: {
      availability_cells: [
        "1|08:00",
        "1|08:30",
        "1|09:00",
        "1|09:30",
        "1|10:00",
        "1|10:30",
        "2|09:00",
        "2|09:30"
      ]
    }

    assert_redirected_to settings_url
    rules = user.availability_rules.order(:weekday, :start_minute)
    assert_equal 2, rules.count
    assert_equal [1, 8 * 60, 11 * 60], [rules.first.weekday, rules.first.start_minute, rules.first.end_minute]
    assert_equal [2, 9 * 60, 10 * 60], [rules.second.weekday, rules.second.start_minute, rules.second.end_minute]
  end

  test "settings owns professional whatsapp configuration" do
    user = User.create!(name: "WhatsApp Settings", email: "whatsapp-settings@example.com", password: "password123")
    post sign_in_url, params: { email: user.email, password: "password123" }

    get ai_assistant_url
    assert_response :success
    assert_no_match "Owner WhatsApp", response.body
    assert_no_match "Your WhatsApp number", response.body

    get settings_url
    assert_response :success
    assert_match "Owner WhatsApp", response.body
    assert_match "Your WhatsApp number", response.body

    patch professional_whatsapp_settings_url, params: {
      ai_setting: {
        use_professional_whatsapp: "1",
        professional_whatsapp_phone: "  +598 99 123 456  "
      }
    }

    assert_redirected_to settings_url
    setting = user.reload.ai_setting
    assert setting.use_professional_whatsapp?
    assert_equal "+598 99 123 456", setting.professional_whatsapp_phone
  end

  test "session form offers CLP and owner can mark a session paid" do
    user = User.create!(name: "Payments Pro", email: "mark-paid@example.com", password: "password123")
    client = user.clients.create!(name: "Client Paid", email: "client-paid@example.com", phone: "+598 99 333 333")
    session_record = user.sessions.create!(
      client: client,
      title: "Payment check",
      start_time: Time.zone.parse("2026-05-08 09:00"),
      end_time: Time.zone.parse("2026-05-08 10:00"),
      price_cents: 25_000,
      currency: "CLP",
      payment_status: "pending"
    )

    post sign_in_url, params: { email: user.email, password: "password123" }

    get new_session_url
    assert_response :success
    assert_match "CLP", response.body

    patch mark_paid_session_url(session_record)
    assert_redirected_to payments_url

    session_record.reload
    assert session_record.payment_paid?
    payment_record = session_record.payment_records.last
    assert_equal "paid", payment_record.status
    assert_equal 25_000, payment_record.amount_cents
    assert_equal "CLP", payment_record.currency
    assert_equal client, payment_record.client

    get session_url(session_record)
    assert_response :success
    assert_select ".header-actions form[action='#{mark_paid_session_path(session_record)}']", count: 0
  end

  test "session detail offers mark as paid while payment is pending" do
    user = User.create!(name: "Detail Payment", email: "detail-payment@example.com", password: "password123")
    client = user.clients.create!(name: "Pending Client", phone: "+598 99 123 777")
    session_record = user.sessions.create!(
      client: client,
      title: "Pending Session",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      payment_status: "pending"
    )
    post sign_in_url, params: { email: user.email, password: "password123" }

    get session_url(session_record)

    assert_response :success
    assert_select ".header-actions form[action='#{mark_paid_session_path(session_record)}']" do
      assert_select "button", text: "Mark as paid"
    end
  end
end
