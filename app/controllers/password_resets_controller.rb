class PasswordResetsController < ApplicationController
  before_action :require_guest!

  def new
  end

  def create
    user = User.find_by_normalized_email(params[:email])
    PasswordMailer.with(user: user, token: user.generate_password_reset_token!).reset.deliver_later if user

    redirect_to sign_in_path, notice: "If that email exists, Sessia sent password reset instructions."
  end

  def edit
    @user = find_user_by_token
    redirect_to new_password_reset_path, alert: "That password reset link is invalid or expired." unless @user
  end

  def update
    @user = find_user_by_token
    unless @user
      redirect_to new_password_reset_path, alert: "That password reset link is invalid or expired."
      return
    end

    if @user.update(password_params)
      @user.clear_password_reset_token!
      sign_in(@user)
      redirect_to dashboard_path, notice: "Your password has been updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def find_user_by_token
    digest = User.digest_token(params[:token])
    user = User.find_by(password_reset_token_digest: digest)
    user if user&.password_reset_token_valid?
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
