class ClientPortalsController < ClientPortalBaseController
  before_action :set_client

  def show
    @client.mark_linked!
    @sessions = @client.sessions.chronological.where("start_time >= ?", Time.current.beginning_of_day).limit(12)
    @message = @client.messages.new
    @messages = @client.messages.where.not(direction: "internal_note").recent_first.limit(16).to_a.reverse
  end

  private

  def set_client
    @client = Client.includes(:user).find_by!(portal_token: params[:token])
  end
end
