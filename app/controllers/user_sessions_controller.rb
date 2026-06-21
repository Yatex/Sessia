class UserSessionsController < ApplicationController
  before_action :require_guest!, only: %i[new create]

  def new
  end

  def create
    user = User.find_by_normalized_email(params[:email])

    if user&.authenticate(params[:password])
      sign_in(user)
      redirect_to dashboard_path, notice: t("flash.auth.signed_in")
    else
      flash.now[:alert] = t("flash.auth.invalid")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out
    redirect_to root_path, notice: t("flash.auth.signed_out")
  end
end
