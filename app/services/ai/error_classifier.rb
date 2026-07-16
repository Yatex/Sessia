module Ai
  class ErrorClassifier
    Classification = Data.define(:category, :delivery_status, :retryable)

    CONFIGURATION_CODES = %w[21656 21612 63016].freeze
    PERMANENT_CODES = %w[21211 21610 63024].freeze

    def self.call(error)
      metadata = error.respond_to?(:provider_metadata) ? error.provider_metadata.to_h.deep_stringify_keys : {}
      code = metadata["error_code"].to_s
      status = metadata["http_status"].to_i
      message = error.message.to_s.downcase

      return Classification.new("provider_configuration", "failed_configuration", false) if CONFIGURATION_CODES.include?(code) || message.include?("content variables") || message.include?("not configured") || message.include?("template validation")
      return Classification.new("provider_permanent", "failed_permanent", false) if PERMANENT_CODES.include?(code) || status.in?(400..499)
      return Classification.new("provider_temporary", "failed_retryable", true) if status >= 500 || error.is_a?(Timeout::Error) || error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)
      return Classification.new("ai_timeout", nil, true) if message.include?("timed out")
      return Classification.new("ai_invalid_response", nil, false) if error.is_a?(JSON::ParserError) || error.class.name.include?("Zod")

      Classification.new("execution_failed", nil, false)
    end
  end
end
