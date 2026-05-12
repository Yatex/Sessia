# frozen_string_literal: true

class StripeBilling
  Plan = Struct.new(:tier, :name, :monthly_price, :description, :price_env_key, :client_limit, keyword_init: true) do
    def price
      return "Free" if monthly_price.to_i.zero?

      "$#{monthly_price}/mo"
    end

    def client_limit_label
      "Up to #{client_limit} active clients"
    end

    def covers_client_count?(client_count)
      client_count.to_i <= client_limit
    end
  end

  Result = Struct.new(:url, :error, keyword_init: true) do
    def success?
      error.blank?
    end
  end

  TRIAL_PLAN = Plan.new(
    tier: "trial",
    name: "Free trial",
    monthly_price: 0,
    description: "Try Sessia with your first clients before choosing a paid plan.",
    price_env_key: nil,
    client_limit: 5
  ).freeze

  PLANS = [
    Plan.new(
      tier: "starter",
      name: "Starter",
      monthly_price: 29,
      description: "For a focused solo practice getting Sessia running.",
      price_env_key: "STRIPE_PRICE_ID_STARTER",
      client_limit: 10
    ),
    Plan.new(
      tier: "pro",
      name: "Pro",
      monthly_price: 49,
      description: "For a busier professional with a deeper active roster.",
      price_env_key: "STRIPE_PRICE_ID_PRO",
      client_limit: 35
    ),
    Plan.new(
      tier: "studio",
      name: "Studio",
      monthly_price: 89,
      description: "For small practices managing a larger client base.",
      price_env_key: "STRIPE_PRICE_ID_STUDIO",
      client_limit: 100
    )
  ].freeze

  class << self
    def plans
      PLANS
    end

    def all_plans
      [TRIAL_PLAN, *PLANS]
    end

    def recommended_plan_for(client_count)
      plans.find { |plan| plan.covers_client_count?(client_count) } || plans.last
    end

    def create_checkout_session(user:, plan_tier:, success_url:, cancel_url:, client_count: nil)
      plan = plan_for(plan_tier)
      return failure("Choose a valid Sessia plan.") unless plan
      return failure("Free trial is created automatically for new accounts.") if plan.tier == "trial"

      client_count = client_count.to_i
      return failure("#{plan.name} supports #{plan.client_limit_label.downcase}; choose a larger plan for #{client_count} active clients.") unless plan.covers_client_count?(client_count)

      price_id = ENV[plan.price_env_key].presence || ENV["STRIPE_PRICE_ID"].presence
      return failure("Stripe price is not configured. Set #{plan.price_env_key}.") if price_id.blank?
      return failure("Stripe secret key is not configured.") if ENV["STRIPE_SECRET_KEY"].blank?

      customer_id = ensure_customer!(user)
      checkout_session = Stripe::Checkout::Session.create(
        mode: "subscription",
        customer: customer_id,
        success_url: success_url,
        cancel_url: cancel_url,
        line_items: [{ price: price_id, quantity: 1 }],
        metadata: metadata_for(user, plan, client_count),
        subscription_data: { metadata: metadata_for(user, plan, client_count) }
      )

      user.subscriptions.create!(
        plan_tier: plan.tier,
        status: "pending",
        provider: "stripe",
        provider_subscription_id: checkout_session.id,
        provider_plan_id: price_id
      )

      Result.new(url: checkout_session.url)
    rescue Stripe::StripeError => e
      failure(e.message)
    end

    def create_portal_session(user:, return_url:)
      return failure("No Stripe customer is linked to this account yet.") if user.stripe_customer_id.blank?
      return failure("Stripe secret key is not configured.") if ENV["STRIPE_SECRET_KEY"].blank?

      portal_session = Stripe::BillingPortal::Session.create(
        customer: user.stripe_customer_id,
        return_url: return_url
      )

      Result.new(url: portal_session.url)
    rescue Stripe::StripeError => e
      failure(e.message)
    end

    def construct_event(payload:, signature:)
      secret = ENV["STRIPE_WEBHOOK_SECRET"].to_s
      raise Stripe::SignatureVerificationError.new("Missing STRIPE_WEBHOOK_SECRET", signature) if secret.blank?

      Stripe::Webhook.construct_event(payload, signature, secret)
    end

    def sync_event(event)
      case event.type
      when "checkout.session.completed"
        handle_checkout_completed(event_object(event))
      when "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"
        upsert_subscription(event_object(event))
      when "invoice.payment_failed"
        mark_subscription_past_due(event_object(event))
      when "invoice.paid", "invoice.payment_succeeded"
        sync_subscription_from_invoice(event_object(event))
      end
    end

    def plan_for(tier)
      all_plans.find { |plan| plan.tier == tier.to_s }
    end

    private

    def ensure_customer!(user)
      return user.stripe_customer_id if user.stripe_customer_id.present?

      customer = Stripe::Customer.create(email: user.email, name: user.name, metadata: { user_id: user.id })
      user.update!(stripe_customer_id: customer.id)
      customer.id
    end

    def handle_checkout_completed(data)
      user = find_user_from_metadata(data["metadata"]) || User.find_by(stripe_customer_id: data["customer"])
      return unless user

      user.update!(stripe_customer_id: data["customer"]) if data["customer"].present?
      subscription_id = data["subscription"]
      return if subscription_id.blank?

      upsert_subscription(subscription_data(subscription_id))
    end

    def sync_subscription_from_invoice(data)
      subscription_id = data["subscription"] ||
        data.dig("parent", "subscription_details", "subscription") ||
        data.dig("lines", "data", 0, "parent", "subscription_item_details", "subscription")
      return if subscription_id.blank?

      upsert_subscription(subscription_data(subscription_id))
    rescue Stripe::StripeError => e
      Rails.logger.warn("[StripeBilling] invoice subscription sync failed: #{e.message}")
    end

    def mark_subscription_past_due(data)
      subscription_id = data["subscription"]
      return if subscription_id.blank?

      subscription = Subscription.find_by(provider: "stripe", provider_subscription_id: subscription_id)
      subscription&.past_due!
    end

    def upsert_subscription(data)
      metadata = data["metadata"] || {}
      user = find_user_from_metadata(metadata) || User.find_by(stripe_customer_id: data["customer"])
      return unless user

      price_id = subscription_price_id(data)
      plan_tier = tier_for_price_id(price_id) || metadata["plan_tier"].presence || "starter"
      subscription = Subscription.find_by(provider: "stripe", provider_subscription_id: data["id"])
      subscription ||= user.subscriptions.where(provider: "stripe", provider_plan_id: price_id, status: "pending").order(created_at: :desc).first
      subscription ||= user.subscriptions.new(provider: "stripe")

      user.update!(stripe_customer_id: data["customer"]) if data["customer"].present? && user.stripe_customer_id != data["customer"]
      subscription.update!(
        plan_tier: plan_tier,
        status: local_status(data["status"], data["cancel_at_period_end"]),
        provider_subscription_id: data["id"],
        provider_plan_id: price_id || subscription.provider_plan_id,
        current_period_start: timestamp_to_time(data["current_period_start"]) || timestamp_to_time(data.dig("items", "data", 0, "current_period_start")),
        current_period_end: timestamp_to_time(data["current_period_end"]) || timestamp_to_time(data.dig("items", "data", 0, "current_period_end")),
        trial_ends_at: timestamp_to_time(data["trial_end"]),
        cancel_at_period_end: data["cancel_at_period_end"] == true,
        quantity: data.dig("items", "data", 0, "quantity").presence || 1
      )
    end

    def subscription_data(subscription_id)
      Stripe::Subscription.retrieve(id: subscription_id, expand: ["items.data.price"]).to_hash.deep_stringify_keys
    end

    def event_object(event)
      event.data.object.to_hash.deep_stringify_keys
    end

    def find_user_from_metadata(metadata)
      User.find_by(id: metadata&.fetch("user_id", nil))
    end

    def metadata_for(user, plan, client_count)
      {
        user_id: user.id,
        plan_tier: plan.tier,
        client_limit: plan.client_limit,
        active_client_count: client_count,
        product: "sessia"
      }
    end

    def tier_for_price_id(price_id)
      return if price_id.blank?

      plans.find { |plan| ENV[plan.price_env_key].present? && ENV[plan.price_env_key] == price_id }&.tier
    end

    def subscription_price_id(data)
      data.dig("items", "data", 0, "price", "id") || data.dig("items", "data", 0, "price")
    end

    def local_status(stripe_status, cancel_at_period_end)
      return "cancelled" if cancel_at_period_end

      case stripe_status.to_s
      when "trialing" then "trialing"
      when "active" then "active"
      when "past_due", "unpaid" then "past_due"
      when "canceled" then "cancelled"
      when "incomplete_expired" then "expired"
      else "pending"
      end
    end

    def timestamp_to_time(value)
      Time.zone.at(value.to_i) if value.present?
    end

    def failure(message)
      Result.new(error: message)
    end
  end
end
