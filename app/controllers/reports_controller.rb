class ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    @filter_professionals = workspace_professionals
    @selected_professional_id = scoped_professional_id(params[:user_id])
    @month_start = Date.current.beginning_of_month
    @month_end = Date.current.end_of_month
    @sessions = analytics_sessions_scope.where(start_time: @month_start.beginning_of_day..@month_end.end_of_day)
    @completed_count = @sessions.completed.count
    @cancelled_count = @sessions.cancelled.count
    @payment_pending_count = @sessions.where(payment_status: %i[pending overdue]).count
    @scheduled_count = @sessions.scheduled.count
    @paid_revenue_cents = @sessions.where(payment_status: :paid).sum(:price_cents)
    @unpaid_revenue_cents = @sessions.where(payment_status: %i[pending overdue]).sum(:price_cents)
    @active_client_count = analytics_clients_scope.active.count
  end

  private

  def scoped_professional_id(user_id)
    return if user_id.blank?

    workspace_professionals.where(id: user_id).pick(:id)
  end

  def analytics_sessions_scope
    scope = workspace_sessions
    scope = scope.where(user_id: @selected_professional_id) if @selected_professional_id.present?
    scope
  end

  def analytics_clients_scope
    scope = workspace_clients
    scope = scope.where(user_id: @selected_professional_id) if @selected_professional_id.present?
    scope
  end
end
