class SignUpsController < ApplicationController
  before_action :require_guest!

  def new
    @user = User.new(time_zone: User::DEFAULT_TIME_ZONE)
  end

  def create
    @user = User.new(user_params)

    if @user.save
      sign_in(@user)
      redirect_to dashboard_path, notice: t("flash.auth.welcome")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :time_zone, :account_type)
  end
end
