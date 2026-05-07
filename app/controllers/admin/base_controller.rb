module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    private

    def require_admin!
      return if current_user.admin?

      redirect_to dashboard_path, alert: "Admin access is required."
    end
  end
end
