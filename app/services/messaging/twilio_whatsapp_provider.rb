require "base64"
require "json"
require "net/http"
require "uri"

module Messaging
  class TwilioWhatsappProvider
    TWILIO_BASE_URL = "https://api.twilio.com/2010-04-01".freeze

    class DeliveryError < StandardError
      attr_reader :provider_metadata

      def initialize(message, provider_metadata: {})
        @provider_metadata = provider_metadata.compact
        super(message)
      end
    end

    def initialize(
      account_sid: ENV["TWILIO_ACCOUNT_SID"],
      auth_token: ENV["TWILIO_AUTH_TOKEN"],
      from: ENV["TWILIO_WHATSAPP_FROM"],
      http_client: Net::HTTP
    )
      @account_sid = account_sid.to_s.strip
      @auth_token = auth_token.to_s.strip
      @from = from.to_s.strip
      @http_client = http_client
    end

    def configured?
      account_sid.present? && auth_token.present? && from.present?
    end

    def deliver(to:, body:, template: nil)
      raise "Twilio WhatsApp is not configured." unless configured?

      uri = URI.parse("#{TWILIO_BASE_URL}/Accounts/#{account_sid}/Messages.json")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(account_sid, auth_token)
      form_data = {
        "From" => Messaging::WhatsappAddress.twilio_address(from),
        "To" => Messaging::WhatsappAddress.twilio_address(to)
      }
      if template.present?
        form_data["ContentSid"] = template.fetch("content_sid")
        form_data["ContentVariables"] = JSON.generate(template_variables(template))
      else
        form_data["Body"] = body
      end
      form_data["StatusCallback"] = status_callback_url if status_callback_url.present?
      request.set_form_data(form_data)

      response = http_client.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      parsed = JSON.parse(response.body)

      unless response.code.to_i.between?(200, 299)
        raise DeliveryError.new(
          "Twilio WhatsApp send failed: #{parsed["message"].presence || response.body}",
          provider_metadata: provider_error_metadata(
            parsed: parsed,
            response: response,
            template: template,
            form_data: form_data
          )
        )
      end

      {
        provider: "twilio_whatsapp",
        external_id: parsed["sid"],
        status: parsed["status"].presence,
        error_code: parsed["error_code"].presence,
        error_message: parsed["error_message"].presence
      }
    rescue JSON::ParserError
      raise "Twilio WhatsApp returned invalid JSON."
    end

    private

    attr_reader :account_sid, :auth_token, :from, :http_client

    def status_callback_url
      ENV["TWILIO_STATUS_CALLBACK_URL"].presence
    end

    def template_variables(template)
      template.fetch("variables", {})
        .to_h
        .transform_keys(&:to_s)
        .transform_values { |value| value.to_s.squish }
    end

    def provider_error_metadata(parsed:, response:, template:, form_data:)
      {
        name: "twilio_whatsapp",
        status: "failed",
        http_status: response.code.to_i,
        error_code: parsed["code"].presence || parsed["error_code"].presence,
        error_message: parsed["message"].presence,
        more_info: parsed["more_info"].presence,
        template: template_debug(template),
        request: {
          content_sid: form_data["ContentSid"].presence,
          content_variables: form_data["ContentVariables"].presence
        }.compact
      }
    end

    def template_debug(template)
      return if template.blank?

      template.to_h.deep_stringify_keys.slice(
        "key", "name", "locale", "content_sid", "variable_names", "semantic_variables", "variables"
      )
    end
  end
end
