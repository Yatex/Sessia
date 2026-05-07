class ClientPortalMessagesController < ClientPortalBaseController
  before_action :set_client

  def create
    @message = @client.messages.new(message_params)
    @message.user = @client.user
    @message.direction = "inbound"
    @message.status = "sent"
    @message.channel = Client::WHATSAPP_CHANNEL
    @message.sent_at = Time.current

    if @message.save
      process_with_ai(@message)
      redirect_to client_portal_path(@client.portal_token), notice: "Your message was sent to #{@client.user.name}."
    else
      @client.mark_linked!
      @sessions = @client.sessions.chronological.where("start_time >= ?", Time.current.beginning_of_day).limit(12)
      @messages = @client.messages.where.not(direction: "internal_note").recent_first.limit(16).to_a.reverse
      render "client_portals/show", status: :unprocessable_entity
    end
  end

  private

  def set_client
    @client = Client.includes(:user).find_by!(portal_token: params[:token])
  end

  def message_params
    permitted = params.require(:message).permit(:subject, :body, :session_id)
    permitted[:session_id] = @client.sessions.find_by(id: permitted[:session_id])&.id if permitted[:session_id].present?
    permitted
  end

  def process_with_ai(message)
    Ai::InboundMessageProcessor.new(message: message).call
  rescue StandardError => error
    Rails.logger.warn("Client portal AI processing skipped for message #{message.id}: #{error.class}: #{error.message}")
  end
end
