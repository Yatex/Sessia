class ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    @month_start = Date.current.beginning_of_month
    @month_end = Date.current.end_of_month
    @sessions = current_user.sessions.where(start_time: @month_start.beginning_of_day..@month_end.end_of_day)
    @completed_count = @sessions.completed.count
    @cancelled_count = @sessions.cancelled.count
    @payment_pending_count = @sessions.where(payment_status: %i[pending overdue]).count
    @scheduled_count = @sessions.scheduled.count
    @paid_revenue_cents = @sessions.where(payment_status: :paid).sum(:price_cents)
    @unpaid_revenue_cents = @sessions.where(payment_status: %i[pending overdue]).sum(:price_cents)
    @active_client_count = current_user.clients.active.count
  end
end
