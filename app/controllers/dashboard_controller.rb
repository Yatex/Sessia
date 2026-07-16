class DashboardController < ApplicationController
  before_action :authenticate_user!

  SLOT_MINUTES = 30
  AGENDA_SPANS = %w[week three_days day].freeze
  AGENDA_DENSITIES = %w[compact comfortable].freeze

  def index
    @view_mode = params[:view] == "month" ? "month" : "week"
    @agenda_span = agenda_preference(:agenda_span, params[:agenda_span], AGENDA_SPANS, "week")
    @agenda_density = agenda_preference(:agenda_density, params[:agenda_density], AGENDA_DENSITIES, "compact")
    @selected_date = parse_date_param
    @filter_professionals = workspace_professionals
    @selected_professional_id = scoped_professional_id(params[:user_id])
    @dashboard_user = @selected_professional_id.present? ? @filter_professionals.find(@selected_professional_id) : current_user
    @studio_resource_view = @view_mode == "week" && studio_workspace? && @selected_professional_id.blank?
    @schedule_block = current_user.schedule_blocks.new(
      starts_at: Time.current.beginning_of_hour + 1.hour,
      ends_at: Time.current.beginning_of_hour + 2.hours
    )

    if @view_mode == "month"
      prepare_month_view
    else
      prepare_week_view
    end

    @sessions_by_day = @sessions.group_by { |session_record| session_record.start_time.to_date }
    @free_slots_by_day = @calendar_days.index_with { |day| free_slot_count_for_day(day) }
    summary_sessions = @view_mode == "month" ? sessions_in_current_month : @sessions
    @summary = {
      total: summary_sessions.size,
      confirmed: summary_sessions.count(&:confirmation_confirmed?),
      pending_confirmations: summary_sessions.count(&:confirmation_pending?),
      pending_payments: summary_sessions.count { |session_record| session_record.payment_pending? || session_record.payment_overdue? || session_record.payment_partially_paid? },
      needs_follow_up: summary_sessions.count(&:needs_follow_up?)
    }
    @schedule_blocks = @dashboard_user.schedule_blocks.active.upcoming.chronological.limit(12)
  end

  def schedule_block
    target_user = target_schedule_block_user
    result = Availability::Blocker.new(user: target_user, attributes: schedule_block_params).call
    affected_count = result.affected_sessions.size
    notice = t("dashboard.block_time.saved")
    notice = "#{notice} #{t("dashboard.block_time.affected", count: affected_count)}" if affected_count.positive?

    redirect_to dashboard_path(view: params[:view].presence || "week", date: params[:date].presence || Date.current.iso8601, user_id: params[:user_id].presence), notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_path(view: params[:view].presence || "week", date: params[:date].presence || Date.current.iso8601, user_id: params[:user_id].presence),
      alert: error.record.errors.full_messages.to_sentence.presence || "Blocked time could not be saved."
  end

  def destroy_schedule_block
    block = ScheduleBlock.where(user_id: workspace_user_ids).find(params[:block_id])
    block.cancel!

    redirect_to dashboard_path(view: params[:view].presence || "week", date: params[:date].presence || Date.current.iso8601, user_id: params[:user_id].presence), notice: t("dashboard.block_time.removed")
  end

  private

  def prepare_week_view
    @week_start = @selected_date.beginning_of_week(:monday)
    prepare_agenda_range
    @availability_calendar = Availability::Calendar.new(@dashboard_user)
    if @studio_resource_view
      @calendar_days = (@week_start..(@week_start + 6.days)).to_a
      prepare_studio_resource_day_view
      return
    end

    @sessions = dashboard_sessions_scope.includes(:client, :user).for_week(@week_start).chronological.to_a
    @time_slots = build_time_slots(@sessions)
    @sessions_by_slot = sessions_by_slot(@sessions)
    @available_slots_by_key = @availability_calendar.slot_availability_for(@calendar_days, slot_minutes: SLOT_MINUTES, duration_minutes: SLOT_MINUTES)
  end

  def prepare_month_view
    @month_start = @selected_date.beginning_of_month
    @calendar_start = @month_start.beginning_of_week(:monday)
    @calendar_end = @month_start.end_of_month.end_of_week(:monday)
    @calendar_days = (@calendar_start..@calendar_end).to_a
    @period_title = I18n.l(@month_start, format: :month_year)
    @previous_date = @month_start.prev_month
    @next_date = @month_start.next_month
    @availability_calendar = Availability::Calendar.new(@dashboard_user)
    @sessions = dashboard_sessions_scope.includes(:client, :user)
      .where(start_time: @calendar_start.beginning_of_day..@calendar_end.end_of_day)
      .chronological
  end

  def prepare_studio_resource_day_view
    @resource_day = @selected_date.to_date
    @period_title = I18n.l(@resource_day, format: :long)
    @resource_professionals = current_user.studio_teachers.order(Arel.sql("LOWER(name) ASC")).to_a
    @resource_calendars = @resource_professionals.index_with { |professional| Availability::Calendar.new(professional) }
    @sessions = Session.where(user_id: @resource_professionals.map(&:id))
      .includes(:client, :user)
      .where(start_time: @resource_day.beginning_of_day..@resource_day.end_of_day)
      .chronological
      .to_a
    @time_slots = build_resource_time_slots(@sessions)
    @sessions_by_professional_slot = sessions_by_professional_slot(@sessions)
    @available_slots_by_professional_key = resource_available_slots
  end

  def parse_date_param
    Date.parse(params[:date].presence || params[:week].to_s)
  rescue ArgumentError
    Date.current
  end

  def prepare_agenda_range
    case @agenda_span
    when "day"
      @calendar_days = [@selected_date]
      @period_title = I18n.l(@selected_date, format: :long)
      @previous_date = @selected_date - 1.day
      @next_date = @selected_date + 1.day
    when "three_days"
      range_end = @selected_date + 2.days
      @calendar_days = (@selected_date..range_end).to_a
      @period_title = "#{I18n.l(@selected_date, format: :short)} - #{I18n.l(range_end, format: :short)}"
      @previous_date = @selected_date - 3.days
      @next_date = @selected_date + 3.days
    else
      range_end = @week_start + 6.days
      @calendar_days = (@week_start..range_end).to_a
      @period_title = "#{I18n.l(@week_start, format: :short)} - #{I18n.l(range_end, format: :short)}"
      @previous_date = @week_start - 7.days
      @next_date = @week_start + 7.days
    end
  end

  def agenda_preference(key, requested_value, allowed_values, default)
    session[key] = requested_value if allowed_values.include?(requested_value)
    allowed_values.include?(session[key]) ? session[key] : default
  end

  def sessions_in_current_month
    @sessions.select { |session_record| session_record.start_time.to_date.month == @month_start.month }
  end

  def build_time_slots(sessions)
    working_slots = @availability_calendar.working_slot_minutes_for(@calendar_days, slot_minutes: SLOT_MINUTES)
    session_slots = sessions.flat_map do |session_record|
      start_minutes = floor_to_slot(minutes_into_day(session_record.start_time))
      end_minutes = ceil_to_slot(minutes_into_day(session_record.end_time))
      (start_minutes...end_minutes).step(SLOT_MINUTES).to_a
    end

    (working_slots + session_slots).uniq.sort
  end

  def build_resource_time_slots(sessions)
    working_slots = @resource_calendars.values.flat_map do |calendar|
      calendar.working_slot_minutes_for([@resource_day], slot_minutes: SLOT_MINUTES)
    end
    session_slots = sessions.flat_map do |session_record|
      start_minutes = floor_to_slot(minutes_into_day(session_record.start_time))
      end_minutes = ceil_to_slot(minutes_into_day(session_record.end_time))
      (start_minutes...end_minutes).step(SLOT_MINUTES).to_a
    end

    (working_slots + session_slots).uniq.sort
  end

  def sessions_by_slot(sessions)
    @calendar_days.each_with_object({}) do |day, slots|
      @time_slots.each do |slot_minutes|
        slot_start = slot_time(day, slot_minutes)
        slot_end = slot_start + SLOT_MINUTES.minutes
        slots[[day, slot_minutes]] = sessions.select do |session_record|
          session_record.start_time < slot_end && session_record.end_time > slot_start
        end
      end
    end
  end

  def sessions_by_professional_slot(sessions)
    @resource_professionals.each_with_object({}) do |professional, slots|
      @time_slots.each do |slot_minutes|
        slot_start = slot_time(@resource_day, slot_minutes)
        slot_end = slot_start + SLOT_MINUTES.minutes
        slots[[professional.id, slot_minutes]] = sessions.select do |session_record|
          session_record.user_id == professional.id &&
            session_record.start_time < slot_end &&
            session_record.end_time > slot_start
        end
      end
    end
  end

  def resource_available_slots
    @resource_professionals.each_with_object({}) do |professional, lookup|
      calendar = @resource_calendars.fetch(professional)
      calendar.slot_availability_for([@resource_day], slot_minutes: SLOT_MINUTES, duration_minutes: SLOT_MINUTES).each do |(_day, slot_minutes), slot|
        lookup[[professional.id, slot_minutes]] = slot
      end
    end
  end

  def free_slot_count_for_day(day)
    if @studio_resource_view
      @resource_calendars.values.sum { |calendar| calendar.free_slot_count_for_day(day, duration_minutes: SLOT_MINUTES) }
    else
      @availability_calendar.free_slot_count_for_day(day, duration_minutes: SLOT_MINUTES)
    end
  end

  def slot_time(day, slot_minutes)
    Time.zone.local(day.year, day.month, day.day, slot_minutes / 60, slot_minutes % 60)
  end

  def minutes_into_day(time)
    time.in_time_zone.hour * 60 + time.in_time_zone.min
  end

  def floor_to_slot(minutes)
    (minutes / SLOT_MINUTES) * SLOT_MINUTES
  end

  def ceil_to_slot(minutes)
    ((minutes + SLOT_MINUTES - 1) / SLOT_MINUTES) * SLOT_MINUTES
  end

  def schedule_block_params
    params.require(:schedule_block).permit(:title, :starts_at, :ends_at, :notes)
  end

  def target_schedule_block_user
    return current_user unless studio_workspace?

    workspace_professionals.find_by(id: params[:user_id]) || current_user
  end

  def scoped_professional_id(user_id)
    return if user_id.blank?

    workspace_professionals.where(id: user_id).pick(:id)
  end

  def dashboard_sessions_scope
    scope = workspace_sessions
    scope = scope.where(user_id: @selected_professional_id) if @selected_professional_id.present?
    scope
  end

end
