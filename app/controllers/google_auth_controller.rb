class GoogleAuthController < ApplicationController
  before_action :require_guest!, only: %i[connect callback]

  def connect
    unless GoogleAuth::Client.configured?
      redirect_to auth_redirect_path, alert: "Google sign-in is not configured yet."
      return
    end

    session[:google_auth_state] = SecureRandom.hex(24)
    session[:google_auth_origin] = auth_origin
    session[:google_auth_time_zone] = supported_time_zone(params[:time_zone])

    redirect_to GoogleAuth::Client.authorization_url(
      redirect_uri: google_auth_redirect_uri,
      state: session[:google_auth_state]
    ), allow_other_host: true
  end

  def callback
    if params[:error].present?
      redirect_to auth_redirect_path, alert: "Google sign-in was cancelled."
      return
    end

    unless valid_oauth_state?
      redirect_to auth_redirect_path, alert: "Google sign-in could not be verified. Please try again."
      return
    end

    tokens = GoogleAuth::Client.exchange_code(code: params[:code], redirect_uri: google_auth_redirect_uri)
    profile = GoogleAuth::Client.userinfo(access_token: tokens.fetch("access_token"))
    user = find_or_create_google_user(profile)

    sign_in(user)
    redirect_to dashboard_path, notice: "Signed in with Google."
  rescue GoogleAuth::Client::Error, ActiveRecord::RecordInvalid => error
    redirect_to auth_redirect_path, alert: error.message
  ensure
    session.delete(:google_auth_state)
    session.delete(:google_auth_origin)
    session.delete(:google_auth_time_zone)
  end

  private

  def find_or_create_google_user(profile)
    uid = profile.fetch("id").to_s
    email = profile.fetch("email").to_s.strip.downcase
    raise GoogleAuth::Client::Error, "Google account email is not verified." unless profile["verified_email"] == true
    raise GoogleAuth::Client::Error, "Google did not return an email address." if email.blank?

    user = User.find_by(google_uid: uid) || User.find_by_normalized_email(email)
    if user
      if user.google_uid.present? && user.google_uid != uid
        raise GoogleAuth::Client::Error, "This email is already linked to another Google account."
      end

      user.update!(
        google_uid: user.google_uid.presence || uid,
        google_avatar_url: profile["picture"].presence || user.google_avatar_url
      )
      return user
    end

    User.create!(
      name: profile["name"].presence || email.split("@").first.humanize,
      email: email,
      password: SecureRandom.urlsafe_base64(32),
      password_confirmation: nil,
      time_zone: session[:google_auth_time_zone].presence || User::DEFAULT_TIME_ZONE,
      google_uid: uid,
      google_avatar_url: profile["picture"].presence
    )
  rescue KeyError
    raise GoogleAuth::Client::Error, "Google did not return the required profile information."
  end

  def valid_oauth_state?
    params[:state].present? &&
      session[:google_auth_state].present? &&
      ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, session[:google_auth_state].to_s)
  end

  def google_auth_redirect_uri
    ENV["GOOGLE_AUTH_REDIRECT_URI"].presence || google_auth_callback_url
  end

  def auth_origin
    params[:origin].presence_in(%w[sign_up sign_in]) || "sign_in"
  end

  def auth_redirect_path
    session[:google_auth_origin] == "sign_up" ? sign_up_path : sign_in_path
  end

  def supported_time_zone(value)
    zone = ActiveSupport::TimeZone[value.to_s]
    zone&.tzinfo&.identifier
  end
end
