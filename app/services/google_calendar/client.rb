require "json"
require "net/http"
require "uri"

module GoogleCalendar
  class Client
    AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
    USERINFO_ENDPOINT = "https://www.googleapis.com/oauth2/v2/userinfo"
    CALENDAR_API_BASE = "https://www.googleapis.com/calendar/v3"
    SCOPES = [
      "openid",
      "email",
      "https://www.googleapis.com/auth/calendar.events"
    ].freeze

    class Error < StandardError; end

    attr_reader :connection

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
        access_type: "offline",
        include_granted_scopes: "true",
        prompt: "consent"
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

    def self.ensure_configured!
      return if configured?

      raise Error, "Google Calendar is not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
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
      raise Error, "Google Calendar returned an invalid response."
    end

    def initialize(connection)
      @connection = connection
    end

    def userinfo
      get_json(USERINFO_ENDPOINT)
    end

    def upsert_session_event(session_record)
      ensure_access_token!

      if session_record.google_calendar_event_id.present?
        patch_event(session_record)
      else
        create_event(session_record)
      end
    end

    def refresh_access_token!
      response = self.class.post_form(
        TOKEN_ENDPOINT,
        client_id: ENV.fetch("GOOGLE_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"),
        refresh_token: connection.refresh_token,
        grant_type: "refresh_token"
      )

      connection.access_token = response.fetch("access_token")
      connection.access_token_expires_at = Time.current + response.fetch("expires_in", 3600).to_i.seconds
      connection.connected!
      connection.update!(error_message: nil)
    end

    private

    def create_event(session_record)
      post_json(calendar_events_url(connection.calendar_id), event_payload(session_record))
    end

    def patch_event(session_record)
      patch_json(calendar_event_url(connection.calendar_id, session_record.google_calendar_event_id), event_payload(session_record))
    rescue Error
      post_json(calendar_events_url(connection.calendar_id), event_payload(session_record))
    end

    def ensure_access_token!
      self.class.ensure_configured!
      raise Error, "Google Calendar is disconnected." unless connection.connected?
      raise Error, "Google Calendar refresh token is missing. Reconnect Google Calendar." if connection.refresh_token.blank?

      refresh_access_token! if connection.access_token_expired?
    end

    def event_payload(session_record)
      {
        summary: "#{session_record.title} - #{session_record.client.name}",
        description: event_description(session_record),
        start: {
          dateTime: session_record.start_time.iso8601,
          timeZone: session_record.user.time_zone
        },
        end: {
          dateTime: session_record.end_time.iso8601,
          timeZone: session_record.user.time_zone
        },
        extendedProperties: {
          private: {
            sessia_session_id: session_record.id.to_s,
            sessia_user_id: session_record.user_id.to_s
          }
        }
      }
    end

    def event_description(session_record)
      [
        "Sessia session",
        "Client: #{session_record.client.name}",
        "Confirmation: #{session_record.confirmation_status.humanize}",
        "Payment: #{session_record.payment_status.humanize}",
        session_record.notes.presence
      ].compact.join("\n")
    end

    def calendar_events_url(calendar_id)
      "#{CALENDAR_API_BASE}/calendars/#{escape(calendar_id)}/events"
    end

    def calendar_event_url(calendar_id, event_id)
      "#{calendar_events_url(calendar_id)}/#{escape(event_id)}"
    end

    def escape(value)
      URI.encode_www_form_component(value.to_s)
    end

    def get_json(url)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{connection.access_token}"

      self.class.perform_request(uri, request)
    end

    def post_json(url, payload)
      json_request(Net::HTTP::Post, url, payload)
    end

    def patch_json(url, payload)
      json_request(Net::HTTP::Patch, url, payload)
    end

    def json_request(klass, url, payload)
      uri = URI(url)
      request = klass.new(uri)
      request["Authorization"] = "Bearer #{connection.access_token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      self.class.perform_request(uri, request)
    end
  end
end
