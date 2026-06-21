module PaymentAccounts
  class MercadoPagoController < ApplicationController
    before_action :authenticate_user!

    def connect
      unless MercadoPago::Client.configured?
        redirect_to settings_path, alert: t("flash.mercado_pago.not_configured")
        return
      end

      state = SecureRandom.urlsafe_base64(24)
      session[:mercado_pago_oauth_state] = state
      redirect_to MercadoPago::Client.new.authorization_url(state: state), allow_other_host: true
    end

    def callback
      unless valid_state?
        redirect_to settings_path, alert: t("flash.mercado_pago.connection_failed")
        return
      end

      response = MercadoPago::Client.new.exchange_code(params[:code].to_s)
      unless response.success?
        account.update!(status: "error", last_error: response.error_message)
        redirect_to settings_path, alert: response.error_message
        return
      end

      body = response.body
      account.mark_connected!(
        provider_user_id: body["user_id"].presence&.to_s,
        access_token: body["access_token"],
        refresh_token: body["refresh_token"],
        token_expires_at: body["expires_in"].present? ? Time.current + body["expires_in"].to_i.seconds : 180.days.from_now
      )
      AuditLog.record!(user: current_user, actor: current_user, event: "mercado_pago_connected", auditable: account)
      redirect_to settings_path, notice: t("flash.mercado_pago.connected")
    ensure
      session.delete(:mercado_pago_oauth_state)
    end

    def disconnect
      if account.connected?
        account.mark_disconnected!
        AuditLog.record!(user: current_user, actor: current_user, event: "mercado_pago_disconnected", auditable: account)
      end

      redirect_to settings_path, notice: t("flash.mercado_pago.disconnected")
    end

    private

    def account
      @account ||= current_user.payment_accounts.find_or_initialize_by(provider: PaymentAccount::PROVIDER_MERCADO_PAGO)
    end

    def valid_state?
      params[:code].present? &&
        params[:state].present? &&
        session[:mercado_pago_oauth_state].present? &&
        ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, session[:mercado_pago_oauth_state].to_s)
    end
  end
end
