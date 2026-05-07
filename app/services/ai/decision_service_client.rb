require "json"
require "net/http"
require "uri"

module Ai
  class DecisionServiceClient
    DEFAULT_ENDPOINT_URL = "http://127.0.0.1:8788/decide".freeze
    DEFAULT_OPEN_TIMEOUT = 3
    DEFAULT_READ_TIMEOUT = 30

    def initialize(
      endpoint_url: ENV["SESSIA_AI_SERVICE_URL"].presence || DEFAULT_ENDPOINT_URL,
      open_timeout: ENV.fetch("SESSIA_AI_SERVICE_OPEN_TIMEOUT", DEFAULT_OPEN_TIMEOUT).to_i,
      read_timeout: ENV.fetch("SESSIA_AI_SERVICE_READ_TIMEOUT", DEFAULT_READ_TIMEOUT).to_i,
      http_client: Net::HTTP
    )
      @endpoint_url = endpoint_url
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @http_client = http_client
    end

    def decide(payload)
      uri = normalized_endpoint_uri
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["X-Sessia-Source"] = "rails"
      request.body = JSON.generate(payload)

      response = http_client.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) do |http|
        http.request(request)
      end

      parsed = JSON.parse(response.body)
      return parsed if response.code.to_i.between?(200, 299) && parsed.is_a?(Hash)

      raise StandardError, error_message(response, parsed)
    rescue JSON::ParserError => error
      raise StandardError, "AI decision service returned invalid JSON: #{error.message}"
    rescue Errno::ECONNREFUSED, SocketError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => error
      raise StandardError, "Could not reach the AI decision service at #{endpoint_url}: #{error.message}"
    end

    private

    attr_reader :endpoint_url, :open_timeout, :read_timeout, :http_client

    def normalized_endpoint_uri
      uri = URI.parse(endpoint_url)
      return uri unless uri.path.blank? || uri.path == "/"

      uri.path = "/decide"
      uri
    end

    def error_message(response, parsed)
      nested = parsed.is_a?(Hash) ? parsed["error"] : nil
      message =
        if nested.is_a?(Hash)
          nested["message"]
        elsif nested.is_a?(String)
          nested
        end

      message ||= parsed["message"] if parsed.is_a?(Hash)
      message ||= "AI decision service request failed."
      "#{message} (HTTP #{response.code})"
    end
  end
end
