class PaymentsController < ApplicationController
  before_action :authenticate_user!

  def index
    @filters = payment_filter_params
    @payment_clients = current_user.clients.alphabetical

    all_sessions = filtered_payment_sessions.to_a
    @sessions = all_sessions.reject(&:payment_not_tracked?)
    @client_payment_rows = client_payment_rows(all_sessions)
    @summary = {
      paid: @sessions.count { |session_record| session_record.payment_paid? },
      unpaid: @sessions.count(&:payment_attention?)
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

      {
        client: client,
        unpaid_count: unpaid_sessions.size,
        unpaid_cents: unpaid_sessions.sum(&:price_cents),
        paid_count: paid_sessions.size,
        paid_cents: paid_sessions.sum(&:price_cents)
      }
    end.sort_by { |row| [-row[:unpaid_count], row[:client].name] }
  end
end
