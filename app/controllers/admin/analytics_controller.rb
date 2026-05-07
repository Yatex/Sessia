module Admin
  class AnalyticsController < Admin::BaseController
    PLAN_MRR = {
      "starter" => 19,
      "pro" => 39,
      "studio" => 79
    }.freeze

    def index
      active_subscriptions = Subscription.active_or_trialing
      paying_subscriptions = active_subscriptions.stripe_backed
      admin_granted_subscriptions = active_subscriptions.admin_granted

      @metrics = {
        total_users: User.count,
        admins: User.admins.count,
        active_clients: Client.active.count,
        scheduled_sessions: Session.scheduled.count,
        active_subscriptions: active_subscriptions.count,
        paying_subscriptions: paying_subscriptions.count,
        admin_granted_subscriptions: admin_granted_subscriptions.count,
        users_without_active_subscription: User.where.not(id: active_subscriptions.select(:user_id)).count,
        estimated_mrr: estimated_mrr(paying_subscriptions)
      }

      @subscriptions_by_tier = active_subscriptions.group(:plan_tier).count
      @paying_by_tier = paying_subscriptions.group(:plan_tier).count
      @recent_users = User.order(created_at: :desc).limit(8)
      @recent_subscriptions = Subscription.includes(:user).order(updated_at: :desc).limit(8)
    end

    private

    def estimated_mrr(scope)
      scope.group(:plan_tier).count.sum do |tier, count|
        PLAN_MRR.fetch(tier.to_s, 0) * count
      end
    end
  end
end
