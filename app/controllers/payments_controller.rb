class PaymentsController < ApplicationController
  before_action :authenticate_user!

  def index
    @filters = payment_filter_params
    @payment_clients = current_user.clients.alphabetical

    all_sessions = filtered_payment_sessions.to_a
    @sessions = all_sessions.reject(&:payment_not_tracked?)
    @records = filtered_payment_records.limit(20)
    @client_payment_rows = client_payment_rows(all_sessions)
    @summary = {
      pending: @sessions.count { |session_record| session_record.payment_pending? },
      overdue: @sessions.count { |session_record| session_record.payment_overdue? },
      paid: @sessions.count { |session_record| session_record.payment_paid? },
      unpaid_cents: @sessions.select(&:payment_attention?).sum(&:price_cents),
      paid_cents: @sessions.select(&:payment_paid?).sum(&:price_cents)
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

  def filtered_payment_records
    scope = current_user.payment_records.includes(:client, :session).recent
    scope = scope.where(client_id: scoped_client_id(@filters[:client_id])) if @filters[:client_id].present?
    scope = scope.where(status: @filters[:payment_status]) if PaymentRecord.statuses.key?(@filters[:payment_status])

    starts_on = parse_filter_date(@filters[:date_from])
    ends_on = parse_filter_date(@filters[:date_to])
    scope = scope.where(due_on: starts_on..) if starts_on
    scope = scope.where(due_on: ..ends_on) if ends_on
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
      upcoming_sessions = sessions.select do |session_record|
        session_record.start_time >= Time.current && !session_record.cancelled? && !session_record.no_show?
      end

      next if tracked_sessions.empty? && upcoming_sessions.empty?

      behind_sessions = tracked_sessions.select(&:payment_attention?)
      paid_sessions = tracked_sessions.select(&:payment_paid?)

      {
        client: client,
        behind_count: behind_sessions.size,
        behind_cents: behind_sessions.sum(&:price_cents),
        overdue_count: behind_sessions.count(&:payment_overdue?),
        paid_count: paid_sessions.size,
        paid_cents: paid_sessions.sum(&:price_cents),
        upcoming_count: upcoming_sessions.size,
        paid_ahead_count: upcoming_sessions.count(&:payment_paid?),
        next_session: upcoming_sessions.min_by(&:start_time)
      }
    end.sort_by { |row| [-row[:behind_count], row[:client].name] }
  end
end
