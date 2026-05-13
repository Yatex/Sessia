class SessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_session, only: %i[show edit update destroy mark_paid sync_google_calendar]
  before_action :load_clients, only: %i[new create edit update]
  before_action :load_calendar_connection, only: %i[show new create edit update]

  SESSION_PICKER_DAYS = 7
  SESSION_PICKER_SLOT_MINUTES = 30

  def index
    @filters = session_filter_params
    @filter_clients = current_user.clients.alphabetical
    @sessions = current_user.sessions.includes(:client).chronological
    @sessions = @sessions.where(client_id: scoped_client_id(@filters[:client_id])) if @filters[:client_id].present?
    @sessions = @sessions.where(status: @filters[:status]) if Session.statuses.key?(@filters[:status])
    @sessions = @sessions.where(confirmation_status: @filters[:confirmation_status]) if Session.confirmation_statuses.key?(@filters[:confirmation_status])
    @sessions = @sessions.where(payment_status: @filters[:payment_status]) if Session.payment_statuses.key?(@filters[:payment_status])
    @sessions = apply_recurrence_filter(@sessions, @filters[:recurrence])
    @sessions = apply_session_date_filters(@sessions, @filters[:date_from], @filters[:date_to])
  end

  def show
  end

  def new
    start_time = parsed_start_time || default_available_start_time || Time.current.beginning_of_hour + 1.hour
    client_id = current_user.clients.where(id: params[:client_id]).pick(:id) if params[:client_id].present?
    @session = current_user.sessions.new(
      client_id: client_id,
      start_time: start_time,
      end_time: start_time + 50.minutes,
      title: "Session",
      payment_status: "pending",
      currency: "USD",
      sync_to_google_calendar: @calendar_connection&.sync_sessions? || false
    )
    load_available_start_options
  end

  def create
    @session = current_user.sessions.new(session_params)

    if @session.save
      after_session_saved(@session)
      redirect_to @session, notice: "Session scheduled."
    else
      load_available_start_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_available_start_options
  end

  def update
    if @session.update(session_params)
      after_session_saved(@session)
      redirect_to @session, notice: "Session updated."
    else
      load_available_start_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @session.destroy
    redirect_to sessions_path, notice: "Session removed."
  end

  def mark_paid
    @session.mark_paid!
    redirect_back fallback_location: payments_path, notice: t("payments.mark_paid_notice")
  end

  def sync_google_calendar
    if GoogleCalendar::SyncSession.new(@session).call
      redirect_to @session, notice: "Session synced to Google Calendar."
    else
      redirect_to @session, alert: @session.google_calendar_sync_error.presence || "Session could not sync to Google Calendar."
    end
  end

  private

  def set_session
    @session = current_user.sessions.includes(:client).find(params[:id])
  end

  def load_clients
    @clients = current_user.clients.active.alphabetical
  end

  def load_calendar_connection
    @calendar_connection = current_user.calendar_connection
  end

  def load_available_start_options
    duration = @session&.duration_minutes.to_i.positive? ? @session.duration_minutes : 60
    availability_calendar = Availability::Calendar.new(current_user)
    slots = Availability::FreeSlotFinder.new(current_user).call(
      from: Time.current.beginning_of_day,
      days: 45,
      duration_minutes: duration,
      limit: 120,
      exclude_session: @session&.persisted? ? @session : nil
    )
    @available_start_options = slots.map { |slot| [slot.label, slot.value] }
    current_value = datetime_local_value(@session&.start_time)

    if current_value.present? && @available_start_options.none? { |_label, value| value == current_value }
      @available_start_options.unshift(["Current time - #{@session.start_time.in_time_zone.strftime("%a %b %-d, %H:%M")}", current_value])
    end

    @session_start_value = current_value
    @session_picker_days = session_picker_days
    @session_picker_slots_by_key = availability_calendar.slot_availability_for(
      @session_picker_days,
      slot_minutes: SESSION_PICKER_SLOT_MINUTES,
      duration_minutes: duration,
      exclude_session: @session&.persisted? ? @session : nil
    )
    selected_slot_minute = @session&.start_time ? floor_to_picker_slot(minutes_into_day(@session.start_time)) : nil
    @session_picker_time_slots = (
      availability_calendar.working_slot_minutes_for(@session_picker_days, slot_minutes: SESSION_PICKER_SLOT_MINUTES) +
      Array(selected_slot_minute)
    ).compact.uniq.sort
  end

  def session_params
    permitted = params.require(:session).permit(
      :client_id,
      :title,
      :start_time,
      :end_time,
      :price,
      :currency,
      :status,
      :confirmation_status,
      :payment_status,
      :sync_to_google_calendar,
      :recurrence_frequency,
      :recurrence_rule,
      :notes,
      recurrence_days: []
    )

    if permitted[:client_id].present?
      permitted[:client_id] = current_user.clients.find(permitted[:client_id]).id
    end

    permitted
  end

  def after_session_saved(session_record)
    RecurringSessionGenerator.new(session_record).generate!
    sync_sessions_to_google_calendar(session_record) if session_record.sync_to_google_calendar?
  end

  def sync_sessions_to_google_calendar(session_record)
    records = [session_record]
    if session_record.recurring_series?
      records += session_record.generated_sessions.where("start_time >= ?", Time.current.beginning_of_day).limit(100)
    end

    records.each do |record|
      record.update_column(:sync_to_google_calendar, true) unless record.sync_to_google_calendar?
      GoogleCalendar::SyncSession.new(record).call
    end
  end

  def session_filter_params
    params.permit(:client_id, :status, :confirmation_status, :payment_status, :recurrence, :date_from, :date_to)
  end

  def scoped_client_id(client_id)
    current_user.clients.where(id: client_id).pick(:id)
  end

  def apply_recurrence_filter(scope, recurrence)
    case recurrence
    when "one_off"
      scope.where(recurring: false, parent_session_id: nil)
    when "recurrent"
      scope.where(recurring: true, parent_session_id: nil)
    when "generated"
      scope.where.not(parent_session_id: nil)
    else
      scope
    end
  end

  def apply_session_date_filters(scope, date_from, date_to)
    starts_on = parse_filter_date(date_from)&.beginning_of_day
    ends_on = parse_filter_date(date_to)&.end_of_day

    scope = scope.where(start_time: starts_on..) if starts_on
    scope = scope.where(start_time: ..ends_on) if ends_on
    scope
  end

  def parse_filter_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def parsed_start_time
    return Time.zone.parse(params[:start_at]) if params[:start_at].present?
    return if params[:date].blank?

    Time.zone.parse("#{params[:date]} 09:00")
  rescue ArgumentError
    nil
  end

  def default_available_start_time
    Availability::FreeSlotFinder.new(current_user).call(
      from: Time.current.beginning_of_hour,
      days: 14,
      duration_minutes: 60,
      limit: 1
    ).first&.starts_at
  end

  def datetime_local_value(time)
    time&.in_time_zone&.strftime("%Y-%m-%dT%H:%M")
  end

  def session_picker_days
    base = (@session&.start_time || Time.current).to_date.beginning_of_week(:monday)
    (base...(base + SESSION_PICKER_DAYS.days)).to_a
  end

  def floor_to_picker_slot(minutes)
    (minutes / SESSION_PICKER_SLOT_MINUTES) * SESSION_PICKER_SLOT_MINUTES
  end

  def minutes_into_day(time)
    local = time.in_time_zone
    local.hour * 60 + local.min
  end
end
