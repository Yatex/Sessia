module Admin
  class UsersController < Admin::BaseController
    PER_PAGE = 30

    before_action :set_user, only: %i[extend_subscription update_role]

    def index
      @filters = filter_params.to_h
      scope = User.includes(:subscriptions, :clients).order(created_at: :desc)
      scope = scope.where("email ILIKE ? OR name ILIKE ?", "%#{User.sanitize_sql_like(@filters[:query])}%", "%#{User.sanitize_sql_like(@filters[:query])}%") if @filters[:query].present?
      scope = scope.where(role: @filters[:role]) if User.roles.key?(@filters[:role])
      scope = filter_by_subscription(scope, @filters[:subscription])

      @page = [params[:page].to_i, 1].max
      @total_count = scope.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @users = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
      @plans = StripeBilling.plans
    end

    def extend_subscription
      end_at = parse_end_at(params[:end_date])
      plan = StripeBilling.plan_for(params[:plan_tier])

      unless end_at && plan
        redirect_to admin_users_path(preserved_query_params), alert: "Choose a valid plan and end date."
        return
      end

      subscription = @user.subscriptions.admin_granted.order(created_at: :desc).first
      subscription ||= @user.subscriptions.build(provider: "admin", quantity: 1)
      subscription.update!(
        plan_tier: plan.tier,
        status: "active",
        provider: "admin",
        provider_subscription_id: nil,
        provider_plan_id: "admin_#{plan.tier}",
        current_period_start: [subscription.current_period_start, Time.current].compact.min,
        current_period_end: end_at,
        trial_ends_at: nil,
        cancel_at_period_end: false,
        quantity: subscription.quantity.presence || 1
      )

      redirect_to admin_users_path(preserved_query_params), notice: "Plan extended for #{@user.email} until #{end_at.to_date.to_fs(:long)}."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_users_path(preserved_query_params), alert: error.record.errors.full_messages.to_sentence
    end

    def update_role
      if @user == current_user
        redirect_to admin_users_path(preserved_query_params), alert: "You cannot change your own admin role."
        return
      end

      role = params[:role].to_s
      unless User.roles.key?(role)
        redirect_to admin_users_path(preserved_query_params), alert: "Choose a valid role."
        return
      end

      @user.update!(role: role)
      redirect_to admin_users_path(preserved_query_params), notice: "#{@user.email} is now #{role.humanize.downcase}."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_users_path(preserved_query_params), alert: error.record.errors.full_messages.to_sentence
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def filter_params
      params.permit(:query, :role, :subscription)
    end

    def preserved_query_params
      {
        query: params[:return_query].presence || params[:query],
        role: params[:return_role].presence || params[:role_filter],
        subscription: params[:return_subscription].presence || params[:subscription],
        page: params[:return_page].presence || params[:page]
      }.compact_blank
    end

    def filter_by_subscription(scope, value)
      case value
      when "active"
        scope.where(id: Subscription.active_or_trialing.select(:user_id))
      when "paying"
        scope.where(id: Subscription.active_or_trialing.stripe_backed.select(:user_id))
      when "admin_granted"
        scope.where(id: Subscription.active_or_trialing.admin_granted.select(:user_id))
      when "none"
        scope.where.not(id: Subscription.active_or_trialing.select(:user_id))
      else
        scope
      end
    end

    def parse_end_at(value)
      Date.parse(value.to_s).end_of_day
    rescue ArgumentError
      nil
    end
  end
end
