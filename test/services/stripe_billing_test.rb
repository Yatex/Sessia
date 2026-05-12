require "test_helper"

class StripeBillingTest < ActiveSupport::TestCase
  test "recommends plans by active client count" do
    assert_equal "starter", StripeBilling.recommended_plan_for(1).tier
    assert_equal "pro", StripeBilling.recommended_plan_for(11).tier
    assert_equal "studio", StripeBilling.recommended_plan_for(36).tier
  end

  test "checkout rejects plans that do not cover the active client count" do
    user = User.create!(name: "Billing Pro", email: "billing@example.com", password: "password123")

    result = StripeBilling.create_checkout_session(
      user: user,
      plan_tier: "starter",
      success_url: "http://example.com/success",
      cancel_url: "http://example.com/billing",
      client_count: 12
    )

    assert_not result.success?
    assert_match "supports up to 10 active clients", result.error
  end

  test "checkout rejects free trial because it is automatic" do
    user = User.create!(name: "Trial Billing Pro", email: "trial-billing@example.com", password: "password123")

    result = StripeBilling.create_checkout_session(
      user: user,
      plan_tier: "trial",
      success_url: "http://example.com/success",
      cancel_url: "http://example.com/billing",
      client_count: 1
    )

    assert_not result.success?
    assert_match "created automatically", result.error
  end
end
