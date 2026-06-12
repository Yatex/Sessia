require "net/http"

module MercadoPago
  class Client
    API_BASE = "https://api.mercadopago.com".freeze
    AUTH_BASE = "https://auth.mercadopago.com".freeze

    Response = Struct.new(:success?, :status, :body, :error_message, keyword_init: true)

    def initialize(access_token: nil)
      @access_token = access_token
    end

    def authorization_url(state:)
      uri = URI("#{AUTH_BASE}/authorization")
      uri.query = {
        client_id: env!("MERCADO_PAGO_CLIENT_ID"),
        response_type: "code",
        platform_id: "mp",
        state: state,
        redirect_uri: redirect_uri
      }.to_query
      uri.to_s
    end

    def exchange_code(code)
      post_json("/oauth/token", {
        client_id: env!("MERCADO_PAGO_CLIENT_ID"),
        client_secret: env!("MERCADO_PAGO_CLIENT_SECRET"),
        code: code,
        grant_type: "authorization_code",
        redirect_uri: redirect_uri,
        test_token: sandbox?
      }, authorized: false)
    end

    def create_preference(payload)
      post_json("/checkout/preferences", payload)
    end

    def payment(payment_id)
      get_json("/v1/payments/#{payment_id}")
    end

    def self.configured?
      ENV["MERCADO_PAGO_CLIENT_ID"].present? &&
        ENV["MERCADO_PAGO_CLIENT_SECRET"].present? &&
        ENV["MERCADO_PAGO_REDIRECT_URI"].present?
    end

    def self.sandbox?
      ENV.fetch("MERCADO_PAGO_ENV", "sandbox") == "sandbox"
    end

    private

    attr_reader :access_token

    def post_json(path, payload, authorized: true)
      request(:post, path, payload: payload, authorized: authorized)
    end

    def get_json(path)
      request(:get, path, authorized: true)
    end

    def request(method, path, payload: nil, authorized: true)
      uri = URI("#{API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{access_token}" if authorized
      request.body = JSON.generate(payload) if payload

      response = http.request(request)
      body = parse_body(response.body)
      success = response.code.to_i.between?(200, 299)
      Response.new(
        success?: success,
        status: response.code.to_i,
        body: body,
        error_message: success ? nil : error_message(body, response.code)
      )
    rescue StandardError => error
      Response.new(success?: false, status: nil, body: {}, error_message: error.message)
    end

    def parse_body(body)
      JSON.parse(body.to_s.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def error_message(body, status)
      body["message"].presence || body["error"].presence || "Mercado Pago request failed with HTTP #{status}."
    end

    def env!(key)
      ENV.fetch(key)
    end

    def redirect_uri
      ENV.fetch("MERCADO_PAGO_REDIRECT_URI")
    end

    def sandbox?
      self.class.sandbox?
    end
  end
end
