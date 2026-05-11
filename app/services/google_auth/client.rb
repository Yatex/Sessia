require "json"
require "net/http"
require "uri"

module GoogleAuth
  class Client
    AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
    USERINFO_ENDPOINT = "https://www.googleapis.com/oauth2/v2/userinfo"
    SCOPES = %w[openid email profile].freeze

    class Error < StandardError; end

    def self.configured?
      ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
    end

    def self.authorization_url(redirect_uri:, state:)
      ensure_configured!

      uri = URI(AUTHORIZATION_ENDPOINT)
      uri.query = URI.encode_www_form(
        client_id: ENV.fetch("GOOGLE_CLIENT_ID"),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: SCOPES.join(" "),
        state: state,
        prompt: "select_account"
      )
      uri.to_s
    end

    def self.exchange_code(code:, redirect_uri:)
      ensure_configured!

      post_form(
        TOKEN_ENDPOINT,
        code: code,
        client_id: ENV.fetch("GOOGLE_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"),
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      )
    end

    def self.userinfo(access_token:)
      ensure_configured!

      uri = URI(USERINFO_ENDPOINT)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"

      perform_request(uri, request)
    end

    def self.ensure_configured!
      return if configured?

      raise Error, "Google sign-in is not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
    end

    def self.post_form(url, form_data)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(form_data)

      perform_request(uri, request)
    end

    def self.perform_request(uri, request)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      body = response.body.present? ? JSON.parse(response.body) : {}

      return body if response.is_a?(Net::HTTPSuccess)

      message = body.dig("error", "message") || body["error_description"] || body["error"] || response.message
      raise Error, message
    rescue JSON::ParserError
      raise Error, "Google returned an invalid response."
    end
  end
end
