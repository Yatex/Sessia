require "test_helper"

class MercadoPagoBillingTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:success?, :status, :body, :error_message, keyword_init: true)

  class FakePreferenceClient
    attr_reader :payload

    def initialize(success: true)
      @success = success
    end

    def create_preference(payload)
      @payload = payload
      FakeResponse.new(
        success?: @success,
        status: @success ? 201 : 422,
        body: {
          "id" => "pref_123",
          "init_point" => "https://mercadopago.example/pay",
          "sandbox_init_point" => "https://sandbox.mercadopago.example/pay"
        },
        error_message: @success ? nil : "Preference failed"
      )
    end
  end

  class FakePaymentClient
    def initialize(payload)
      @payload = payload
    end

    def payment(_payment_id)
      FakeResponse.new(success?: true, status: 200, body: @payload)
    end
  end

  setup do
    @user = User.create!(name: "MP Pro", email: "mp-pro@example.com", password: "password123")
    @client = @user.clients.create!(name: "Tamara", phone: "+598 99 123 123")
    @session = @user.sessions.create!(
      client: @client,
      title: "Therapy",
      start_time: 2.days.from_now,
      end_time: 2.days.from_now + 1.hour,
      price_cents: 10_000,
      currency: "ARS",
      payment_required_before_session: true
    )
  end

  test "creates one session charge and keeps it idempotent" do
    assert_difference -> { Charge.count }, 1 do
      @charge = Billing::CreateSessionChargeService.new(@session).call
    end

    assert_equal @charge, Billing::CreateSessionChargeService.new(@session.reload).call
    assert_equal @session, @charge.session
    assert_equal @client, @charge.client
    assert_equal 10_000, @charge.amount_cents
    assert_equal @session.start_time.to_date - 1.day, @charge.due_date
    assert_equal @charge, @session.reload.charge
  end

  test "payment account stores mercado pago tokens encrypted" do
    account = @user.payment_accounts.create!(status: "connected", connected_at: Time.current)
    account.access_token = "access-secret"
    account.refresh_token = "refresh-secret"
    account.save!

    assert_equal "access-secret", account.reload.access_token
    assert_equal "refresh-secret", account.refresh_token
    assert_no_match "access-secret", account.access_token_ciphertext
    assert_no_match "refresh-secret", account.refresh_token_ciphertext
  end

  test "mercado pago webhook signature verifier accepts valid hmac" do
    secret = "mp-webhook-secret"
    timestamp = "1704908010"
    request_id = "request-123"
    data_id = "999999999"
    manifest = "id:#{data_id};request-id:#{request_id};ts:#{timestamp};"
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, manifest)

    verifier = MercadoPago::SignatureVerifier.new(
      headers: {
        "x-signature" => "ts=#{timestamp},v1=#{signature}",
        "x-request-id" => request_id
      },
      params: { "data.id" => data_id },
      secret: secret
    )

    assert verifier.valid?
  end

  test "creates checkout pro preference with external reference and metadata" do
    account = @user.payment_accounts.create!(status: "connected", connected_at: Time.current)
    account.access_token = "seller-token"
    account.save!
    charge = Billing::CreateSessionChargeService.new(@session).call
    client = FakePreferenceClient.new

    result = with_env("APP_HOST" => "https://sessia.org", "MERCADO_PAGO_ENV" => "production") do
      MercadoPago::CreatePreferenceService.new(
        charge: charge,
        success_url: "https://sessia.org/success",
        failure_url: "https://sessia.org/failure",
        pending_url: "https://sessia.org/pending",
        client: client
      ).call
    end

    assert result.success?
    assert_equal "https://mercadopago.example/pay", charge.reload.payment_url
    assert_equal charge.external_reference, client.payload[:external_reference]
    assert_equal "https://sessia.org/webhooks/mercado_pago", client.payload[:notification_url]
    assert_equal charge.id, client.payload[:metadata][:charge_id]
  end

  test "approved webhook payment marks charge and session paid idempotently" do
    charge = Billing::CreateSessionChargeService.new(@session).call
    payload = mercado_pago_payment_payload(charge, amount: 100.0, status: "approved")

    assert_difference -> { Payment.count }, 1 do
      result = MercadoPago::WebhookProcessor.new(params: { "data" => { "id" => "999" } }, client: FakePaymentClient.new(payload)).call
      assert result.success?
    end

    assert_no_difference -> { Payment.count } do
      MercadoPago::WebhookProcessor.new(params: { "data" => { "id" => "999" } }, client: FakePaymentClient.new(payload)).call
    end

    assert charge.reload.paid?
    assert @session.reload.payment_paid?
  end

  test "partial payment marks charge and session partial" do
    charge = Billing::CreateSessionChargeService.new(@session).call
    payload = mercado_pago_payment_payload(charge, amount: 40.0, status: "approved")

    MercadoPago::WebhookProcessor.new(params: { "data" => { "id" => "partial" } }, client: FakePaymentClient.new(payload)).call

    assert charge.reload.partially_paid?
    assert @session.reload.payment_partially_paid?
  end

  test "overpayment creates client credit" do
    charge = Billing::CreateSessionChargeService.new(@session).call
    payload = mercado_pago_payment_payload(charge, amount: 125.0, status: "approved")

    assert_difference -> { CreditLedgerEntry.count }, 1 do
      MercadoPago::WebhookProcessor.new(params: { "data" => { "id" => "overpaid" } }, client: FakePaymentClient.new(payload)).call
    end

    assert_equal 2_500, @client.credit_ledger_entries.last.amount_cents
    assert charge.reload.paid?
  end

  test "manual payment updates charge and session without AI involvement" do
    charge = Billing::CreateSessionChargeService.new(@session).call

    assert_difference -> { Payment.where(provider: "manual").count }, 1 do
      Billing::RecordManualPaymentService.new(charge: charge, amount_cents: 10_000, method: "cash", actor: @user).call
    end

    assert charge.reload.paid?
    assert @session.reload.payment_paid?
  end

  test "ai context exposes read only billing data" do
    charge = Billing::CreateSessionChargeService.new(@session).call
    charge.update!(payment_url: "https://mercadopago.example/pay")
    task = @user.ai_tasks.create!(
      client: @client,
      session: @session,
      trigger_event: "payment_due",
      automation_key: "payment_reminder",
      scheduled_for: Time.current
    )

    payload = Ai::ContextBuilder.new(task: task).call.fetch(:payload)

    assert_equal 10_000, payload.dig(:billing_context, :current_balance_cents)
    assert_equal "https://mercadopago.example/pay", payload.dig(:billing_context, :payment_link_for_next_unpaid_session)
    assert_nil payload.dig(:billing_context, :access_token)
  end

  private

  def mercado_pago_payment_payload(charge, amount:, status:)
    {
      "id" => "mp_#{amount}_#{status}",
      "status" => status,
      "status_detail" => "accredited",
      "transaction_amount" => amount,
      "currency_id" => charge.currency,
      "date_approved" => Time.current.iso8601,
      "external_reference" => charge.external_reference,
      "preference_id" => charge.mercado_pago_preference_id,
      "metadata" => {
        "charge_id" => charge.id,
        "client_id" => charge.client_id,
        "session_id" => charge.session_id,
        "user_id" => charge.user_id
      }
    }
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
