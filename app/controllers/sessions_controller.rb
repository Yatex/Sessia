class SessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_session, only: %i[
    show edit update destroy mark_paid generate_payment_link regenerate_payment_link
    record_manual_payment waive_payment cancel_charge sync_google_calendar
  ]
  before_action :load_clients, only: %i[new create edit update]
  before_action :load_calendar_connection, only: %i[show new create edit update]

  SESSION_PICKER_DAYS = 7
  SESSION_PICKER_SLOT_MINUTES = 30

  def index
    @filters = session_filter_params
    @filter_clients = workspace_clients.includes(:user).alphabetical
    @filter_professionals = workspace_professionals
    @sessions = workspace_sessions.includes(:client, :user).chronological
    @sessions = @sessions.where(user_id: scoped_professional_id(@filters[:user_id])) if @filters[:user_id].present?
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
    client = workspace_clients.find_by(id: params[:client_id]) if params[:client_id].present?
    owner = client&.user || @selected_session_owner || default_session_owner
    billing_profile = client&.billing_profile
    @session = owner.sessions.new(
      client: client,
      start_time: start_time,
      end_time: start_time + 60.minutes,
      title: t("sessions.defaults.title"),
      payment_status: "pending",
      price_cents: billing_profile&.default_session_price_cents.to_i,
      currency: billing_profile&.currency.presence || "ARS",
      payment_required_before_session: billing_profile&.payment_required_before_session || false,
      sync_to_google_calendar: google_calendar_feature_enabled? && (@calendar_connection&.sync_sessions? || false)
    )
    load_available_start_options
  end

  def create
    attributes = session_params
    owner = session_owner_from_attributes(attributes)
    @session = owner.sessions.new(attributes.except(:user_id))

    if @session.save
      after_session_saved(@session)
      redirect_to @session, notice: t("flash.sessions.scheduled")
    else
      load_available_start_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_available_start_options
  end

  def update
    attributes = session_params
    @session.user = session_owner_from_attributes(attributes) if studio_workspace? || attributes[:client_id].present?

    if @session.update(attributes.except(:user_id))
      after_session_saved(@session)
      redirect_to @session, notice: t("flash.sessions.updated")
    else
      load_available_start_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @session.destroy
    redirect_to sessions_path, notice: t("flash.sessions.removed")
  end

  def mark_paid
    @session.mark_paid!
    redirect_back fallback_location: payments_path, notice: t("payments.mark_paid_notice")
  end

  def generate_payment_link
    charge = Billing::CreateSessionChargeService.new(@session).call
    if charge.blank?
      redirect_to @session, alert: t("flash.sessions.add_price_for_link")
      return
    end

    result = create_payment_preference(charge)
    redirect_to @session, result.success? ? { notice: t("flash.sessions.payment_link_ready") } : { alert: result.error_message }
  end

  def regenerate_payment_link
    charge = @session.main_charge || Billing::CreateSessionChargeService.new(@session).call
    if charge.blank?
      redirect_to @session, alert: t("flash.sessions.add_price_for_link")
      return
    end

    result = create_payment_preference(charge, regenerate: true)
    redirect_to @session, result.success? ? { notice: t("flash.sessions.payment_link_regenerated") } : { alert: result.error_message }
  end

  def record_manual_payment
    charge = @session.main_charge || Billing::CreateSessionChargeService.new(@session).call
    if charge.blank?
      redirect_to @session, alert: t("flash.sessions.add_price_for_payment")
      return
    end

    Billing::RecordManualPaymentService.new(
      charge: charge,
      amount_cents: price_to_cents(params[:amount]),
      paid_at: parse_payment_date(params[:paid_on]),
      method: params[:method],
      note: params[:note],
      actor: current_user
    ).call
    redirect_to @session, notice: t("flash.sessions.manual_payment_recorded")
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to @session, alert: error.message
  end

  def waive_payment
    charge = @session.main_charge
    if charge.present?
      charge.update!(status: "forgiven", cancelled_at: Time.current)
      charge.sync_session_payment_status!
      AuditLog.record!(user: charge.user, actor: current_user, event: "charge_forgiven", auditable: charge)
    else
      @session.update!(payment_status: "waived")
    end
    redirect_to @session, notice: t("flash.sessions.payment_waived")
  end

  def cancel_charge
    charge = @session.main_charge
    if charge.present?
      charge.update!(status: "cancelled", cancelled_at: Time.current)
      charge.sync_session_payment_status!
      AuditLog.record!(user: charge.user, actor: current_user, event: "charge_cancelled", auditable: charge)
    end
    redirect_to @session, notice: t("flash.sessions.charge_cancelled")
  end

  def sync_google_calendar
    unless google_calendar_feature_enabled?
      redirect_to @session, alert: t("flash.sessions.google_calendar_unavailable")
      return
    end

    if GoogleCalendar::SyncSession.new(@session).call
      redirect_to @session, notice: t("flash.sessions.google_calendar_synced")
    else
      redirect_to @session, alert: @session.google_calendar_sync_error.presence || t("flash.sessions.google_calendar_failed")
    end
  end

  private

  def set_session
    @session = workspace_sessions.includes(:client, :user).find(params[:id])
  end

  def load_clients
    @session_professionals = workspace_professionals
    @selected_session_owner = selected_session_owner
    @clients = workspace_clients.includes(:user).active.alphabetical
    @clients = @clients.where(user_id: @selected_session_owner.id) if studio_workspace? && @selected_session_owner.present?
  end

  def load_calendar_connection
    @calendar_connection = (@selected_session_owner || @session&.user || current_user).calendar_connection
  end

  def load_available_start_options
    duration = @session&.duration_minutes.to_i.positive? ? @session.duration_minutes : 60
    availability_user = @selected_session_owner || @session&.user || default_session_owner
    availability_calendar = Availability::Calendar.new(availability_user)
    slots = Availability::FreeSlotFinder.new(availability_user).call(
      from: Time.current.beginning_of_day,
      days: 45,
      duration_minutes: duration,
      limit: 120,
      exclude_session: @session&.persisted? ? @session : nil
    )
    @available_start_options = slots.map { |slot| [slot.label, slot.value] }
    @session_picker_start_time = floor_time_to_picker_slot(@session&.start_time)
    @session_picker_end_time = ceil_time_to_picker_slot(@session&.end_time)
    current_value = datetime_local_value(@session_picker_start_time || @session&.start_time)

    if current_value.present? && @available_start_options.none? { |_label, value| value == current_value }
      @available_start_options.unshift(["Current time - #{@session.start_time.in_time_zone.strftime("%a %b %-d, %H:%M")}", current_value])
    end

    @session_start_value = current_value
    @session_end_value = datetime_local_value(@session_picker_end_time || @session&.end_time)
    @session_picker_days = session_picker_days
    @session_picker_slots_by_key = availability_calendar.slot_availability_for(
      @session_picker_days,
      slot_minutes: SESSION_PICKER_SLOT_MINUTES,
      duration_minutes: SESSION_PICKER_SLOT_MINUTES,
      exclude_session: @session&.persisted? ? @session : nil
    )
    selected_slot_minute = @session_picker_start_time ? minutes_into_day(@session_picker_start_time) : nil
    @session_picker_time_slots = (
      availability_calendar.working_slot_minutes_for(@session_picker_days, slot_minutes: SESSION_PICKER_SLOT_MINUTES) +
      Array(selected_slot_minute)
    ).compact.uniq.sort
  end

  def session_params
    permitted = params.require(:session).permit(
      :client_id,
      :user_id,
      :title,
      :start_time,
      :end_time,
      :price,
      :currency,
      :payment_required_before_session,
      :status,
      :confirmation_status,
      :payment_status,
      :sync_to_google_calendar,
      :recurrence_frequency,
      :recurrence_rule,
      :notes,
      recurrence_days: []
    )

    permitted[:user_id] = scoped_professional_id(permitted[:user_id]) if studio_workspace? && permitted[:user_id].present?
    permitted.delete(:user_id) unless studio_workspace?

    client = workspace_clients.find(permitted[:client_id]) if permitted[:client_id].present?
    permitted[:client_id] = client.id if client
    permitted[:user_id] ||= client.user_id if studio_workspace? && client

    permitted
  end

  def after_session_saved(session_record)
    apply_client_billing_defaults(session_record)
    charge = Billing::CreateSessionChargeService.new(session_record).call
    create_payment_preference(charge) if charge.present? && generate_payment_link_requested?
    RecurringSessionGenerator.new(session_record).generate!
    sync_sessions_to_google_calendar(session_record) if google_calendar_feature_enabled? && session_record.sync_to_google_calendar?
  end

  def apply_client_billing_defaults(session_record)
    profile = session_record.client&.billing_profile
    return if profile.blank?

    attributes = {}
    attributes[:price_cents] = profile.default_session_price_cents if session_record.price_cents.to_i.zero? && profile.default_session_price_cents.to_i.positive?
    attributes[:currency] = profile.currency if session_record.currency.blank?
    attributes[:payment_required_before_session] = profile.payment_required_before_session if session_record.payment_required_before_session.nil?
    session_record.update!(attributes) if attributes.present?
  end

  def generate_payment_link_requested?
    ActiveModel::Type::Boolean.new.cast(params.dig(:session, :generate_payment_link))
  end

  def create_payment_preference(charge, regenerate: false)
    MercadoPago::CreatePreferenceService.new(
      charge: charge,
      success_url: session_url(@session, mp_result: "success"),
      failure_url: session_url(@session, mp_result: "failure"),
      pending_url: session_url(@session, mp_result: "pending"),
      regenerate: regenerate
    ).call
  end

  def price_to_cents(value)
    (BigDecimal(value.to_s.tr(",", ".")) * 100).round
  rescue ArgumentError
    0
  end

  def parse_payment_date(value)
    Date.iso8601(value.to_s).in_time_zone
  rescue ArgumentError
    Time.current
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
    params.permit(:client_id, :user_id, :status, :confirmation_status, :payment_status, :recurrence, :date_from, :date_to)
  end

  def scoped_client_id(client_id)
    workspace_clients.where(id: client_id).pick(:id)
  end

  def scoped_professional_id(user_id)
    workspace_professionals.where(id: user_id).pick(:id)
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
    Availability::FreeSlotFinder.new(@selected_session_owner || default_session_owner).call(
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

  def ceil_to_picker_slot(minutes)
    ((minutes + SESSION_PICKER_SLOT_MINUTES - 1) / SESSION_PICKER_SLOT_MINUTES) * SESSION_PICKER_SLOT_MINUTES
  end

  def floor_time_to_picker_slot(time)
    return if time.blank?

    local = time.in_time_zone
    local.beginning_of_day + floor_to_picker_slot(minutes_into_day(local)).minutes
  end

  def ceil_time_to_picker_slot(time)
    return if time.blank?

    local = time.in_time_zone
    local.beginning_of_day + ceil_to_picker_slot(minutes_into_day(local)).minutes
  end

  def minutes_into_day(time)
    local = time.in_time_zone
    local.hour * 60 + local.min
  end

  def google_calendar_feature_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["GOOGLE_CALENDAR_UI_ENABLED"])
  end

  def default_session_owner
    studio_workspace? ? workspace_professionals.first || current_user : current_user
  end

  def selected_session_owner
    return current_user unless studio_workspace?

    user_id = params.dig(:session, :user_id).presence || params[:user_id].presence
    workspace_professionals.find_by(id: user_id) || @session&.user || default_session_owner
  end

  def session_owner_from_attributes(attributes)
    if studio_workspace? && attributes[:user_id].present?
      return workspace_professionals.find(attributes[:user_id])
    end

    return default_session_owner if attributes[:client_id].blank?

    workspace_clients.find(attributes[:client_id]).user
  end
end
