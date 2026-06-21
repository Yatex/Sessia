class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update destroy]

  def index
    @filters = client_filter_params
    @filter_professionals = workspace_professionals
    @clients = workspace_clients.includes(:user).alphabetical
    @clients = @clients.where(user_id: scoped_professional_id(@filters[:user_id])) if @filters[:user_id].present?
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
    @billing_profile = @client.billing_profile || @client.build_billing_profile(user: @client.user)
  end

  def new
    @client = default_client_owner.clients.new(preferred_contact_channel: Client::WHATSAPP_CHANNEL)
  end

  def create
    owner = client_owner_from_params
    @client = owner.clients.new(client_params.except(:user_id))

    if @client.save
      redirect_to @client, notice: t("flash.clients.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @client.update(client_params)
      @client.billing_profile&.update!(user: @client.user)
      redirect_to @client, notice: t("flash.clients.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @client.destroy
      redirect_to clients_path, notice: t("flash.clients.archived")
    else
      redirect_to @client, alert: @client.errors.full_messages.to_sentence
    end
  end

  private

  def set_client
    @client = workspace_clients.find(params[:id])
  end

  def client_params
    permitted = params.require(:client).permit(:user_id, :name, :email, :phone, :status, :notes)
    if studio_workspace? && permitted[:user_id].present?
      permitted[:user_id] = workspace_professionals.find(permitted[:user_id]).id
    else
      permitted.delete(:user_id)
    end
    permitted
  end

  def client_filter_params
    params.permit(:query, :status, :linked, :user_id)
  end

  def default_client_owner
    studio_workspace? ? workspace_professionals.first || current_user : current_user
  end

  def client_owner_from_params
    return current_user unless studio_workspace?

    workspace_professionals.find_by(id: client_params[:user_id]) || default_client_owner
  end

  def scoped_professional_id(user_id)
    workspace_professionals.where(id: user_id).pick(:id)
  end
end
