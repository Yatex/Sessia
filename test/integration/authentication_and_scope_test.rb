require "test_helper"

class AuthenticationAndScopeTest < ActionDispatch::IntegrationTest
  test "sign up explains the automatic free trial" do
    get sign_up_url

    assert_response :success
    assert_match "Your 14-day free trial starts automatically", response.body
    assert_match "No card is required to start", response.body
  end

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

  test "subscriptions page shows active trial state" do
    user = User.create!(name: "Trial Viewer", email: "trial-viewer@example.com", password: "password123")
    post sign_in_url, params: { email: user.email, password: "password123" }

    get subscription_url

    assert_response :success
    assert_match "Free trial active", response.body
    assert_match "Your trial is already running", response.body
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

  test "dashboard supports reusable agenda ranges and remembers density" do
    user = User.create!(name: "Mobile Agenda", email: "mobile-agenda@example.com", password: "password123")
    post sign_in_url, params: { email: user.email, password: "password123" }
    selected_date = Date.new(2026, 7, 15)

    get dashboard_url(view: "week", date: selected_date.iso8601, agenda_span: "three_days", agenda_density: "comfortable")

    assert_response :success
    assert_select ".agenda-grid.agenda-span-three_days.agenda-density-comfortable"
    assert_select ".agenda-grid .week-grid-day", count: 3
    assert_select ".agenda-range-control .active", text: "3 days"
    assert_select ".agenda-density-control .active", text: "Spacious"

    get dashboard_url(view: "week", date: selected_date.iso8601)

    assert_response :success
    assert_select ".agenda-grid.agenda-span-three_days.agenda-density-comfortable"
    assert_select ".agenda-grid .week-grid-day", count: 3
  end

  test "day agenda renders one day while week agenda renders seven" do
    user = User.create!(name: "Agenda Ranges", email: "agenda-ranges@example.com", password: "password123")
    post sign_in_url, params: { email: user.email, password: "password123" }
    selected_date = Date.new(2026, 7, 15)

    get dashboard_url(view: "week", date: selected_date.iso8601, agenda_span: "day")
    assert_select ".agenda-grid.agenda-span-day .week-grid-day", count: 1

    get dashboard_url(view: "week", date: selected_date.iso8601, agenda_span: "week")
    assert_select ".agenda-grid.agenda-span-week .week-grid-day", count: 7
  end

  test "payments page is scoped to current professional charges" do
    user = User.create!(name: "Payments Scope", email: "payments-scope@example.com", password: "password123")
    client = user.clients.create!(name: "Visible Payer", phone: "+598 99 111 600")
    session_record = user.sessions.create!(
      client: client,
      title: "Visible Paid Session",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      price_cents: 12_000,
      currency: "ARS"
    )
    Billing::CreateSessionChargeService.new(session_record).call

    other_user = User.create!(name: "Other Payments", email: "other-payments@example.com", password: "password123")
    other_client = other_user.clients.create!(name: "Hidden Payer", phone: "+598 99 111 601")
    other_session = other_user.sessions.create!(
      client: other_client,
      title: "Hidden Paid Session",
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      price_cents: 30_000,
      currency: "ARS"
    )
    Billing::CreateSessionChargeService.new(other_session).call

    post sign_in_url, params: { email: user.email, password: "password123" }
    get payments_url

    assert_response :success
    assert_match "Visible Payer", response.body
    assert_no_match "Hidden Payer", response.body
  end
end
