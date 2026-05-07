module Messaging
  class WhatsappAddress
    def self.normalize(value)
      value.to_s
        .delete_prefix("whatsapp:")
        .gsub(/[^\d]/, "")
        .presence
    end

    def self.twilio_address(value)
      normalized = value.to_s.strip
      return normalized if normalized.start_with?("whatsapp:")

      digits = normalize(normalized)
      digits.present? ? "whatsapp:+#{digits}" : normalized
    end

    def self.same?(left, right)
      normalize(left).present? && normalize(left) == normalize(right)
    end
  end
end
