class HomeController < ApplicationController
  def index
    redirect_to dashboard_path if authenticated?
  end

  def terms
  end

  def privacy
  end
end
