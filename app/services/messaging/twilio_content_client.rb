require "json"
require "net/http"
require "uri"

module Messaging
  class TwilioContentClient
    BASE_URL = "https://content.twilio.com/v1".freeze

    class ApiError < StandardError
      attr_reader :status, :payload

      def initialize(message, status:, payload: {})
        @status, @payload = status, payload
        super(message)
      end
    end

    def initialize(account_sid: ENV["TWILIO_ACCOUNT_SID"], auth_token: ENV["TWILIO_AUTH_TOKEN"], http_client: Net::HTTP)
      @account_sid = account_sid.to_s.strip
      @auth_token = auth_token.to_s.strip
      @http_client = http_client
    end

    def configured? = account_sid.present? && auth_token.present?

    def contents
      ensure_configured!
      page_url = "#{BASE_URL}/Content?PageSize=100"
      records = []

      while page_url.present?
        payload = request(:get, page_url)
        records.concat(Array(payload["contents"]))
        page_url = payload.dig("meta", "next_page_url").presence
        page_url = "https://content.twilio.com#{page_url}" if page_url&.start_with?("/")
      end
      records
    end

    def fetch(content_sid)
      ensure_configured!
      request(:get, "#{BASE_URL}/Content/#{content_sid}")
    end

    def approval_status(content_sid)
      ensure_configured!
      request(:get, "#{BASE_URL}/Content/#{content_sid}/ApprovalRequests")
    rescue ApiError => error
      return {} if error.status == 404
      raise
    end

    def create(definition)
      ensure_configured!
      request(:post, "#{BASE_URL}/Content", {
        friendly_name: definition.friendly_name,
        language: definition.locale.to_s,
        variables: definition.default_variables,
        types: { "twilio/text" => { body: definition.body } }
      })
    end

    private

    attr_reader :account_sid, :auth_token, :http_client

    def ensure_configured!
      raise ApiError.new("TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN are required.", status: 0) unless configured?
    end

    def request(method, url, body = nil)
      uri = URI.parse(url)
      request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request.basic_auth(account_sid, auth_token)
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      response = http_client.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      payload = JSON.parse(response.body.presence || "{}")
      return payload if response.code.to_i.between?(200, 299)

      raise ApiError.new(
        payload["message"].presence || "Twilio Content API returned HTTP #{response.code}.",
        status: response.code.to_i,
        payload: payload
      )
    rescue JSON::ParserError
      raise ApiError.new("Twilio Content API returned invalid JSON.", status: response&.code.to_i)
    end
  end
end
