class ApplicationController < ActionController::Base
  around_action :use_current_locale
  around_action :use_current_user_time_zone

  helper_method :current_user, :authenticated?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id].present?
  end

  def authenticated?
    current_user.present?
  end

  def authenticate_user!
    return if authenticated?

    redirect_to sign_in_path, alert: "Sign in to continue."
  end

  def require_guest!
    redirect_to dashboard_path if authenticated?
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
  end

  def sign_out
    reset_session
  end

  def use_current_locale(&block)
    I18n.with_locale(locale_for_request, &block)
  end

  def locale_for_request
    locale = current_user&.locale.to_s
    return locale if I18n.available_locales.map(&:to_s).include?(locale)

    locale = cookies[:locale].to_s
    return locale if I18n.available_locales.map(&:to_s).include?(locale)

    I18n.default_locale
  end

  def use_current_user_time_zone(&block)
    Time.use_zone(time_zone_for_request, &block)
  end

  def time_zone_for_request
    current_user&.time_zone.presence || Time.zone
  end
end
