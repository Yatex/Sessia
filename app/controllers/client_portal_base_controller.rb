class ClientPortalBaseController < ApplicationController
  layout "client_portal"

  private

  def time_zone_for_request
    portal_owner_time_zone.presence || super
  end

  def portal_owner_time_zone
    @client&.user&.time_zone.presence ||
      Client.joins(:user).where(portal_token: params[:token]).pick("users.time_zone")
  end
end
