require "test_helper"

class MercadoPagoAccountConnectionTest < ActionDispatch::IntegrationTest
  test "professional connects mercado pago account through oauth callback" do
    user = User.create!(name: "MP Owner", email: "mp-owner@example.com", password: "password123")
    post sign_in_url, params: { email: user.email, password: "password123" }

    with_env(
      "MERCADO_PAGO_CLIENT_ID" => "client-id",
      "MERCADO_PAGO_CLIENT_SECRET" => "client-secret",
      "MERCADO_PAGO_REDIRECT_URI" => "https://sessia.org/payment_accounts/mercado-pago/callback"
    ) do
      get connect_payment_accounts_mercado_pago_url
      assert_response :redirect

      state = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("state")

      with_exchange_code_stub do
        assert_difference -> { PaymentAccount.count }, 1 do
          get callback_payment_accounts_mercado_pago_url, params: { code: "oauth-code", state: state }
        end
      end
    end

    account = user.payment_accounts.find_by!(provider: "mercado_pago")
    assert account.connected?
    assert_equal "seller-123", account.provider_user_id
    assert_equal "mp-access-token", account.access_token
    assert_equal "mp-refresh-token", account.refresh_token
    assert_no_match "mp-access-token", account.access_token_ciphertext
    assert AuditLog.exists?(user: user, event: "mercado_pago_connected")
    assert_redirected_to settings_url
  end

  private

  def with_exchange_code_stub
    original = MercadoPago::Client.instance_method(:exchange_code)
    MercadoPago::Client.define_method(:exchange_code) do |_code|
      MercadoPago::Client::Response.new(
        success?: true,
        status: 200,
        body: {
          "user_id" => "seller-123",
          "access_token" => "mp-access-token",
          "refresh_token" => "mp-refresh-token",
          "expires_in" => 3600
        }
      )
    end
    yield
  ensure
    MercadoPago::Client.define_method(:exchange_code, original)
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
