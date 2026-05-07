require "base64"
require "openssl"

module Messaging
  class TwilioSignatureVerifier
    def initialize(auth_token: ENV["TWILIO_AUTH_TOKEN"], signature_required: nil)
      @auth_token = auth_token.to_s
      @signature_required = signature_required
    end

    def required?
      return signature_required unless signature_required.nil?

      ActiveModel::Type::Boolean.new.cast(ENV["TWILIO_VERIFY_WEBHOOK_SIGNATURE"]) ||
        Rails.env.production? ||
        auth_token.present?
    end

    def valid?(url:, params:, signature:)
      return true unless required?
      return false if auth_token.blank? || signature.blank?

      expected = expected_signature(url: url, params: params)
      secure_compare(expected, signature.to_s)
    end

    def expected_signature(url:, params:)
      data = normalized_url(url).dup
      params.to_h.stringify_keys.sort.each do |key, value|
        data << key << Array(value).join(",")
      end

      Base64.strict_encode64(OpenSSL::HMAC.digest("sha1", auth_token, data))
    end

    private

    attr_reader :auth_token, :signature_required

    def normalized_url(url)
      ENV["TWILIO_WEBHOOK_URL"].presence || url.to_s
    end

    def secure_compare(expected, actual)
      return false if expected.blank? || actual.blank?

      ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(expected),
        ::Digest::SHA256.hexdigest(actual)
      )
    end
  end
end
