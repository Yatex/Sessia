class PasswordMailer < ApplicationMailer
  def reset
    @user = params[:user]
    @token = params[:token]

    mail(to: @user.email, subject: "Reset your Sessia password")
  end
end
