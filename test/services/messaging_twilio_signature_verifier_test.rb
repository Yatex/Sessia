require "test_helper"

class MessagingTwilioSignatureVerifierTest < ActiveSupport::TestCase
  test "validates a twilio signature for url and params" do
    verifier = Messaging::TwilioSignatureVerifier.new(auth_token: "secret", signature_required: true)
    params = {
      "From" => "whatsapp:+59899111222",
      "To" => "whatsapp:+14155238886",
      "Body" => "yes"
    }
    url = "https://sessia.example.com/webhooks/twilio/whatsapp"
    signature = verifier.expected_signature(url: url, params: params)

    assert verifier.valid?(url: url, params: params, signature: signature)
    assert_not verifier.valid?(url: url, params: params, signature: "bad-signature")
  end

  test "is optional when not required and auth token is absent" do
    verifier = Messaging::TwilioSignatureVerifier.new(auth_token: nil, signature_required: false)

    assert verifier.valid?(url: "https://example.com", params: {}, signature: nil)
  end
end
