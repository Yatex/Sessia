require "test_helper"

class AdminAccessTest < ActionDispatch::IntegrationTest
  test "members cannot access admin pages" do
    member = create_user(email: "member-admin-test@example.com")
    sign_in_as(member)

    get admin_analytics_url

    assert_redirected_to dashboard_url
    follow_redirect!
    assert_response :success
    assert_match "Admin access is required.", response.body
  end

  test "admins can view platform analytics and user management" do
    admin = create_user(email: "admin-test@example.com", role: "admin")
    member = create_user(email: "managed-user@example.com")
    member.subscriptions.create!(
      plan_tier: "pro",
      status: "active",
      provider: "stripe",
      provider_subscription_id: "sub_test_managed",
      provider_plan_id: "price_test_pro",
      current_period_start: 1.week.ago,
      current_period_end: 1.month.from_now
    )

    sign_in_as(admin)

    get admin_analytics_url
    assert_response :success
    assert_match "Platform analytics", response.body
    assert_match "Paying plans", response.body

    get admin_users_url
    assert_response :success
    assert_match "Users and plans", response.body
    assert_match "managed-user@example.com", response.body
  end

  test "admins can view AI message monitor" do
    admin = create_user(email: "admin-ai-monitor@example.com", role: "admin")
    member = create_user(email: "ai-monitor-owner@example.com")
    client = member.clients.create!(name: "AI Monitor Client", phone: "+598 99 111 250")
    task = member.ai_tasks.create!(
      client: client,
      trigger_event: "before_session",
      automation_key: "session_reminder",
      status: "failed",
      scheduled_for: 10.minutes.ago,
      processed_at: 8.minutes.ago,
      result_data: {
        "activity_summary" => "Reminder delivery failed.",
        "performed_action" => "send_message",
        "reasoning_summary" => "Reminder was due."
      },
      error_message: "Provider rejected the message."
    )
    member.messages.create!(
      client: client,
      ai_task: task,
      direction: "outbound",
      channel: "whatsapp",
      status: "failed",
      subject: "Reminder",
      body: "Can you confirm?",
      error_message: "Outside WhatsApp conversation window."
    )

    sign_in_as(admin)

    get admin_ai_messages_url

    assert_response :success
    assert_match "AI message monitor", response.body
    assert_match "ai-monitor-owner@example.com", response.body
    assert_match "Outside WhatsApp conversation window", response.body
  end

  test "admins can extend a user subscription" do
    admin = create_user(email: "admin-extend@example.com", role: "admin")
    member = create_user(email: "extend-target@example.com")
    stripe_subscription = member.subscriptions.create!(
      plan_tier: "starter",
      status: "active",
      provider: "stripe",
      provider_subscription_id: "sub_test_extend",
      provider_plan_id: "price_test_starter",
      current_period_start: 1.week.ago,
      current_period_end: 1.week.from_now
    )
    end_date = 2.months.from_now.to_date

    sign_in_as(admin)

    post extend_subscription_admin_user_url(member), params: {
      plan_tier: "studio",
      end_date: end_date.to_s
    }

    assert_redirected_to admin_users_url
    subscription = member.reload.current_subscription
    assert member.subscriptions.admin_granted.exists?
    assert_equal "studio", subscription.plan_tier
    assert_equal "active", subscription.status
    assert_equal "admin", subscription.provider
    assert_equal end_date, subscription.current_period_end.in_time_zone("America/Montevideo").to_date
    assert_equal "starter", stripe_subscription.reload.plan_tier
    assert_equal "stripe", stripe_subscription.provider
  end

  test "admins can update another user's role" do
    admin = create_user(email: "admin-role@example.com", role: "admin")
    member = create_user(email: "promote-target@example.com")

    sign_in_as(admin)

    patch role_admin_user_url(member), params: { role: "admin" }

    assert_redirected_to admin_users_url
    assert member.reload.admin?
  end

  test "admins cannot remove their own admin role" do
    admin = create_user(email: "admin-self@example.com", role: "admin")
    sign_in_as(admin)

    patch role_admin_user_url(admin), params: { role: "member" }

    assert_redirected_to admin_users_url
    assert admin.reload.admin?
  end

  private

  def create_user(email:, role: "member")
    User.create!(
      name: email.split("@").first.humanize,
      email: email,
      password: "password123",
      password_confirmation: "password123",
      role: role,
      time_zone: "America/Montevideo"
    )
  end

  def sign_in_as(user)
    post sign_in_url, params: { email: user.email, password: "password123" }
    assert_redirected_to dashboard_url
  end
end
