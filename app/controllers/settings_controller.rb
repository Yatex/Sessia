class SettingsController < ApplicationController
  before_action :authenticate_user!

  AVAILABILITY_CELL_MINUTES = 30

  def show
    load_settings_context
  end

  def update
    @user = current_user

    if @user.update(user_params)
      redirect_to settings_path, notice: "Account settings updated."
    else
      load_settings_context
      render :show, status: :unprocessable_entity
    end
  end

  def availability
    update_availability_rules!
    redirect_to settings_path, notice: "Working hours updated."
  rescue ActiveRecord::RecordInvalid => error
    load_settings_context
    flash.now[:alert] = error.record.errors.full_messages.to_sentence.presence || "Working hours could not be saved."
    render :show, status: :unprocessable_entity
  end

  def professional_whatsapp
    @ai_setting = current_user.ai_setting || current_user.create_ai_setting!

    if @ai_setting.update(professional_whatsapp_params)
      redirect_to settings_path, notice: "WhatsApp settings updated."
    else
      load_settings_context
      render :show, status: :unprocessable_entity
    end
  end

  def password_reset
    token = current_user.generate_password_reset_token!
    PasswordMailer.with(user: current_user, token: token).reset.deliver_later

    redirect_to settings_path, notice: "Password reset instructions were sent to #{current_user.email}."
  end

  private

  def load_settings_context
    Availability::Defaults.ensure_for(current_user)
    @user = current_user
    @ai_setting = current_user.ai_setting || current_user.create_ai_setting!
    @calendar_connection = current_user.calendar_connection
    @google_calendar_configured = GoogleCalendar::Client.configured?
    @availability_by_weekday = current_user.availability_rules.ordered.to_a.group_by(&:weekday)
  end

  def user_params
    params.require(:user).permit(:name, :email, :time_zone, :locale, :payment_instructions)
  end

  def professional_whatsapp_params
    params.require(:ai_setting).permit(:use_professional_whatsapp, :professional_whatsapp_phone)
  end

  def update_availability_rules!
    rules = build_availability_rules
    AvailabilityRule.transaction do
      current_user.availability_rules.delete_all
      rules.each { |attributes| current_user.availability_rules.create!(attributes) }
    end
  end

  def build_availability_rules
    return build_availability_rules_from_cells if params.key?(:availability_cells)

    rows = params.fetch(:availability, ActionController::Parameters.new).permit!.to_h
    rows.flat_map do |weekday, values|
      next [] unless weekday.to_i.between?(0, 6)
      next [] unless ActiveModel::Type::Boolean.new.cast(values["enabled"])

      [1, 2].filter_map do |index|
        start_minute = AvailabilityRule.minutes_from_time(values["start_time_#{index}"])
        end_minute = AvailabilityRule.minutes_from_time(values["end_time_#{index}"])
        next if start_minute.blank? || end_minute.blank?

        {
          weekday: weekday.to_i,
          start_minute: start_minute,
          end_minute: end_minute,
          enabled: true
        }
      end
    end
  end

  def build_availability_rules_from_cells
    cells = Array(params[:availability_cells]).map(&:to_s)
    cells_by_weekday = cells.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |cell, grouped|
      weekday, slot = cell.split("|", 2)
      next unless weekday.to_i.between?(0, 6)

      minute = AvailabilityRule.minutes_from_time(slot)
      next if minute.blank?

      grouped[weekday.to_i] << minute
    end

    cells_by_weekday.flat_map do |weekday, minutes|
      compress_cell_minutes(weekday, minutes.uniq.sort)
    end
  end

  def compress_cell_minutes(weekday, minutes)
    rules = []
    index = 0

    while index < minutes.length
      start_minute = minutes[index]
      end_minute = start_minute + AVAILABILITY_CELL_MINUTES
      index += 1

      while index < minutes.length && minutes[index] == end_minute
        end_minute += AVAILABILITY_CELL_MINUTES
        index += 1
      end

      rules << {
        weekday: weekday,
        start_minute: start_minute,
        end_minute: end_minute,
        enabled: true
      }
    end

    rules
  end
end
