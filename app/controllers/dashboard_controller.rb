class DashboardController < ApplicationController
  before_action :authenticate_user!

  SLOT_MINUTES = 30

  def index
    @view_mode = params[:view] == "month" ? "month" : "week"
    @selected_date = parse_date_param
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
    @free_slots_by_day = @calendar_days.index_with { |day| @availability_calendar.free_slot_count_for_day(day, duration_minutes: SLOT_MINUTES) }
    summary_sessions = @view_mode == "month" ? sessions_in_current_month : @sessions
    @summary = {
      total: summary_sessions.size,
      confirmed: summary_sessions.count(&:confirmation_confirmed?),
      pending_confirmations: summary_sessions.count(&:confirmation_pending?),
      pending_payments: summary_sessions.count { |session_record| session_record.payment_pending? || session_record.payment_overdue? || session_record.payment_partially_paid? },
      needs_follow_up: summary_sessions.count(&:needs_follow_up?)
    }
    @schedule_blocks = current_user.schedule_blocks.active.upcoming.chronological.limit(12)
    @payment_dashboard = {
      unpaid_sessions: current_user.sessions.where(payment_status: %i[pending overdue partially_paid]).count,
      paid_this_month: current_user.sessions.where(payment_status: :paid, start_time: Time.current.beginning_of_month..Time.current.end_of_month).count,
      overdue_charges: current_user.charges.overdue.count,
      recent_payments: current_user.payments.approved.includes(:client).recent.limit(4),
      clients_with_pending_balance: current_user.charges.unpaid.includes(:client).map(&:client).uniq.first(5)
    }
  end

  def schedule_block
    result = Availability::Blocker.new(user: current_user, attributes: schedule_block_params).call
    affected_count = result.affected_sessions.size
    notice = t("dashboard.block_time.saved")
    notice = "#{notice} #{t("dashboard.block_time.affected", count: affected_count)}" if affected_count.positive?

    redirect_to dashboard_path(view: params[:view].presence || "week", date: params[:date].presence || Date.current.iso8601), notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_path(view: params[:view].presence || "week", date: params[:date].presence || Date.current.iso8601),
      alert: error.record.errors.full_messages.to_sentence.presence || "Blocked time could not be saved."
  end

  def destroy_schedule_block
    block = current_user.schedule_blocks.find(params[:block_id])
    block.cancel!

    redirect_to dashboard_path(view: params[:view].presence || "week", date: params[:date].presence || Date.current.iso8601), notice: t("dashboard.block_time.removed")
  end

  private

  def prepare_week_view
    @week_start = @selected_date.beginning_of_week(:monday)
    @calendar_days = (@week_start..(@week_start + 6.days)).to_a
    @period_title = "#{I18n.l(@week_start, format: :short)} - #{I18n.l(@week_start + 6.days, format: :short)}"
    @previous_date = @week_start - 7.days
    @next_date = @week_start + 7.days
    @availability_calendar = Availability::Calendar.new(current_user)
    @sessions = current_user.sessions.includes(:client).for_week(@week_start).chronological.to_a
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
    @availability_calendar = Availability::Calendar.new(current_user)
    @sessions = current_user.sessions.includes(:client)
      .where(start_time: @calendar_start.beginning_of_day..@calendar_end.end_of_day)
      .chronological
  end

  def parse_date_param
    Date.parse(params[:date].presence || params[:week].to_s)
  rescue ArgumentError
    Date.current
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
end
