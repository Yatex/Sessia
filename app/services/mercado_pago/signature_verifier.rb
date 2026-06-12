module MercadoPago
  class SignatureVerifier
    def initialize(headers:, params:, secret: ENV["MERCADO_PAGO_WEBHOOK_SECRET"])
      @headers = headers
      @params = params
      @secret = secret.to_s
    end

    def valid?
      return true if secret.blank?
      return false if signature_header.blank? || request_id.blank? || timestamp.blank? || signature.blank?

      ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
    end

    private

    attr_reader :headers, :params, :secret

    def expected_signature
      OpenSSL::HMAC.hexdigest("SHA256", secret, manifest)
    end

    def manifest
      parts = []
      parts << "id:#{data_id};" if data_id.present?
      parts << "request-id:#{request_id};"
      parts << "ts:#{timestamp};"
      parts.join
    end

    def data_id
      id = params["data.id"].presence || params.dig("data", "id").presence || params[:data_id].presence
      id.to_s.match?(/[A-Za-z]/) ? id.to_s.downcase : id.to_s
    end

    def signature_header
      headers["x-signature"].presence || headers["X-Signature"].presence
    end

    def request_id
      headers["x-request-id"].presence || headers["X-Request-Id"].presence
    end

    def timestamp
      signature_parts["ts"]
    end

    def signature
      signature_parts["v1"]
    end

    def signature_parts
      @signature_parts ||= signature_header.to_s.split(",").filter_map do |part|
        key, value = part.split("=", 2)
        [key.to_s.strip, value.to_s.strip] if key.present? && value.present?
      end.to_h
    end
  end
end
