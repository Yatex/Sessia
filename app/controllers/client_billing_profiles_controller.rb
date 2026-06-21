class ClientBillingProfilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client

  def update
    profile = @client.billing_profile || @client.build_billing_profile(user: @client.user)
    profile.assign_attributes(profile_params.merge(user: @client.user))

    if profile.save
      redirect_to @client, notice: t("flash.clients.billing_updated")
    else
      @sessions = @client.sessions.chronological.limit(12)
      @billing_profile = profile
      render "clients/show", status: :unprocessable_entity
    end
  end

  private

  def set_client
    @client = workspace_clients.find(params[:client_id])
  end

  def profile_params
    params.require(:client_billing_profile).permit(
      :default_session_price,
      :currency,
      :payment_required_before_session,
      :default_due_timing,
      :custom_due_days_before,
      :active,
      :notes
    )
  end
end
