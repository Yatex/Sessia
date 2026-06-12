class PaymentsController < ApplicationController
  before_action :authenticate_user!

  def index
    @filters = payment_filter_params
    @payment_clients = current_user.clients.alphabetical

    all_sessions = filtered_payment_sessions.to_a
    @sessions = all_sessions.reject(&:payment_not_tracked?)
    @charges = filtered_charges.includes(:client, :session, :payments).recent
    @recent_payments = current_user.payments.includes(:client, :charge).recent.limit(8)
    @client_payment_rows = client_payment_rows(all_sessions)
    @summary = {
      paid: @sessions.count { |session_record| session_record.payment_paid? },
      unpaid: @sessions.count(&:payment_attention?),
      overdue: @charges.overdue.count,
      paid_this_month: current_user.payments.approved.where(paid_at: Time.current.beginning_of_month..Time.current.end_of_month).count
    }
  end

  private

  def filtered_payment_sessions
    scope = current_user.sessions.includes(:client).chronological
    scope = scope.where(client_id: scoped_client_id(@filters[:client_id])) if @filters[:client_id].present?
    scope = scope.where(payment_status: @filters[:payment_status]) if Session.payment_statuses.key?(@filters[:payment_status])

    starts_on = parse_filter_date(@filters[:date_from])&.beginning_of_day
    ends_on = parse_filter_date(@filters[:date_to])&.end_of_day
    scope = scope.where(start_time: starts_on..) if starts_on
    scope = scope.where(start_time: ..ends_on) if ends_on
    scope
  end

  def filtered_charges
    scope = current_user.charges
    scope = scope.where(client_id: scoped_client_id(@filters[:client_id])) if @filters[:client_id].present?
    scope = scope.where(status: @filters[:payment_status]) if Charge.statuses.key?(@filters[:payment_status])
    scope
  end

  def payment_filter_params
    params.permit(:client_id, :payment_status, :date_from, :date_to)
  end

  def scoped_client_id(client_id)
    current_user.clients.where(id: client_id).pick(:id)
  end

  def parse_filter_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def client_payment_rows(session_records)
    session_records.group_by(&:client).filter_map do |client, sessions|
      tracked_sessions = sessions.reject(&:payment_not_tracked?)
      next if tracked_sessions.empty?

      unpaid_sessions = tracked_sessions.select(&:payment_attention?)
      paid_sessions = tracked_sessions.select(&:payment_paid?)
      charges = client.charges.to_a

      {
        client: client,
        unpaid_count: charges.present? ? charges.count { |charge| charge.pending? || charge.overdue? || charge.partially_paid? } : unpaid_sessions.size,
        unpaid_cents: charges.present? ? charges.select { |charge| charge.pending? || charge.overdue? || charge.partially_paid? }.sum(&:amount_cents) : unpaid_sessions.sum(&:price_cents),
        paid_count: charges.present? ? charges.count(&:paid?) : paid_sessions.size,
        paid_cents: charges.present? ? charges.select(&:paid?).sum(&:amount_cents) : paid_sessions.sum(&:price_cents)
      }
    end.sort_by { |row| [-row[:unpaid_count], row[:client].name] }
  end
end
