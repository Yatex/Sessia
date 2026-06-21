class BillingController < ApplicationController
  before_action :authenticate_user!

  def show
    @plans = StripeBilling.plans
    @subscription = current_user.current_subscription || current_user.subscriptions.order(created_at: :desc).first
    @active_client_count = workspace_clients.active.count
    @recommended_plan = StripeBilling.recommended_plan_for(@active_client_count)
  end

  def checkout
    active_client_count = workspace_clients.active.count
    result = StripeBilling.create_checkout_session(
      user: current_user,
      plan_tier: params[:plan],
      success_url: success_subscription_url,
      cancel_url: subscription_url,
      client_count: active_client_count
    )

    if result.success?
      redirect_to result.url, allow_other_host: true
    else
      redirect_to subscription_path, alert: result.error
    end
  end

  def portal
    result = StripeBilling.create_portal_session(user: current_user, return_url: subscription_url)

    if result.success?
      redirect_to result.url, allow_other_host: true
    else
      redirect_to subscription_path, alert: result.error
    end
  end

  def success
    redirect_to subscription_path, notice: "Stripe is processing your subscription."
  end
end
