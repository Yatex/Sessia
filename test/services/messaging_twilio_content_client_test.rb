require "test_helper"

class MessagingTwilioContentClientTest < ActiveSupport::TestCase
  Response = Data.define(:code, :body)

  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def start(_host, _port, use_ssl:)
      raise "SSL required" unless use_ssl
      yield self
    end

    def request(request)
      requests << request
      @responses.shift
    end
  end

  test "creates an official Twilio text Content resource from a catalog definition" do
    http = FakeHttp.new([Response.new("201", { sid: "HX#{'5' * 32}" }.to_json)])
    client = Messaging::TwilioContentClient.new(account_sid: "AC123", auth_token: "secret", http_client: http)
    definition = Messaging::WhatsappTemplateCatalog.definitions.first

    result = client.create(definition)
    payload = JSON.parse(http.requests.first.body)

    assert_equal "HX#{'5' * 32}", result["sid"]
    assert_equal definition.friendly_name, payload["friendly_name"]
    assert_equal definition.locale.to_s, payload["language"]
    assert_equal definition.body, payload.dig("types", "twilio/text", "body")
    assert_equal definition.expected_numbers, payload["variables"].keys
    assert_equal "María", payload.dig("variables", "1")
    assert_match(/^Basic /, http.requests.first["Authorization"])
  end

  test "treats a missing approval resource as unsubmitted" do
    http = FakeHttp.new([Response.new("404", { message: "not found" }.to_json)])
    client = Messaging::TwilioContentClient.new(account_sid: "AC123", auth_token: "secret", http_client: http)

    assert_equal({}, client.approval_status("HX#{'6' * 32}"))
  end
end
