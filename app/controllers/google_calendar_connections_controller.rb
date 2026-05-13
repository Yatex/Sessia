class GoogleCalendarConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_google_calendar_feature_enabled!
  before_action :set_calendar_connection, only: %i[update sync disconnect]
  before_action :require_connected_calendar, only: :sync

  def connect
    unless GoogleCalendar::Client.configured?
      redirect_to settings_path, alert: "Google Calendar is not configured yet."
      return
    end

    session[:google_calendar_oauth_state] = SecureRandom.hex(24)
    redirect_to GoogleCalendar::Client.authorization_url(
      redirect_uri: google_calendar_redirect_uri,
      state: session[:google_calendar_oauth_state]
    ), allow_other_host: true
  end

  def callback
    if params[:error].present?
      redirect_to settings_path, alert: "Google Calendar connection was cancelled."
      return
    end

    unless valid_oauth_state?
      redirect_to settings_path, alert: "Google Calendar connection could not be verified. Please try again."
      return
    end

    tokens = GoogleCalendar::Client.exchange_code(code: params[:code], redirect_uri: google_calendar_redirect_uri)
    connection = current_user.calendar_connection || current_user.build_calendar_connection
    connection.assign_attributes(
      provider: CalendarConnection::PROVIDER_GOOGLE,
      calendar_id: "primary",
      access_token_expires_at: Time.current + tokens.fetch("expires_in", 3600).to_i.seconds,
      sync_sessions: true,
      status: "connected",
      error_message: nil
    )
    connection.access_token = tokens.fetch("access_token")
    connection.refresh_token = tokens["refresh_token"] if tokens["refresh_token"].present? || connection.refresh_token.blank?
    connection.save!
    update_connected_account_email(connection)

    redirect_to settings_path, notice: "Google Calendar connected."
  rescue GoogleCalendar::Client::Error => error
    redirect_to settings_path, alert: error.message
  ensure
    session.delete(:google_calendar_oauth_state)
  end

  def update
    if @calendar_connection.update(calendar_connection_params)
      redirect_to settings_path, notice: "Google Calendar settings updated."
    else
      redirect_to settings_path, alert: @calendar_connection.errors.full_messages.to_sentence
    end
  end

  def sync
    result = GoogleCalendar::SyncUpcomingSessions.new(current_user).call
    message = "#{result[:synced]} upcoming sessions synced to Google Calendar."
    message += " #{result[:failed]} could not sync." if result[:failed].positive?
    redirect_to settings_path, notice: message
  end

  def disconnect
    @calendar_connection.destroy
    current_user.sessions.update_all(sync_to_google_calendar: false)
    redirect_to settings_path, notice: "Google Calendar disconnected."
  end

  private

  def set_calendar_connection
    @calendar_connection = current_user.calendar_connection
    redirect_to settings_path, alert: "Connect Google Calendar first." unless @calendar_connection
  end

  def require_connected_calendar
    redirect_to settings_path, alert: "Reconnect Google Calendar first." unless @calendar_connection.connected?
  end

  def valid_oauth_state?
    params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, session[:google_calendar_oauth_state].to_s)
  end

  def google_calendar_redirect_uri
    ENV["GOOGLE_CALENDAR_REDIRECT_URI"].presence || google_calendar_callback_url
  end

  def update_connected_account_email(connection)
    email = GoogleCalendar::Client.new(connection).userinfo["email"]
    connection.update!(provider_account_email: email) if email.present?
  rescue GoogleCalendar::Client::Error
    nil
  end

  def calendar_connection_params
    params.require(:calendar_connection).permit(:sync_sessions)
  end

  def ensure_google_calendar_feature_enabled!
    return if ActiveModel::Type::Boolean.new.cast(ENV["GOOGLE_CALENDAR_UI_ENABLED"])

    redirect_to settings_path, alert: "Google Calendar connection is temporarily unavailable."
  end
end
