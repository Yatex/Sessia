class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update destroy]

  def index
    @filters = client_filter_params
    @clients = current_user.clients.alphabetical
    @clients = @clients.where(status: @filters[:status]) if Client.statuses.key?(@filters[:status])
    @clients = @clients.where.not(linked_at: nil) if @filters[:linked] == "linked"
    @clients = @clients.where(linked_at: nil) if @filters[:linked] == "unlinked"

    if @filters[:query].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@filters[:query].strip)}%"
      @clients = @clients.where(
        "clients.name ILIKE :query OR clients.email ILIKE :query OR clients.phone ILIKE :query",
        query: query
      )
    end
  end

  def show
    @sessions = @client.sessions.chronological.limit(12)
  end

  def new
    @client = current_user.clients.new(preferred_contact_channel: Client::WHATSAPP_CHANNEL)
  end

  def create
    @client = current_user.clients.new(client_params)

    if @client.save
      redirect_to @client, notice: "Client created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @client.update(client_params)
      redirect_to @client, notice: "Client updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @client.destroy
      redirect_to clients_path, notice: "Client archived from Sessia."
    else
      redirect_to @client, alert: @client.errors.full_messages.to_sentence
    end
  end

  private

  def set_client
    @client = current_user.clients.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :email, :phone, :status, :notes)
  end

  def client_filter_params
    params.permit(:query, :status, :linked)
  end
end
