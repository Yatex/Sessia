require "json"

module Messaging
  class WhatsappTemplateValidator
    Result = Data.define(:valid, :errors, :debug) do
      def valid? = valid
    end

    def call(template)
      data = template.to_h.deep_stringify_keys
      names = Array(data["variable_names"]).map(&:to_s)
      semantic = data["semantic_variables"].to_h.stringify_keys
      numbered = data["variables"].to_h.stringify_keys
      expected_numbers = (1..names.length).map(&:to_s)
      errors = []
      errors << "unsupported_locale" unless data["locale"].to_s.in?(%w[en es])
      errors << "missing_content_sid" if data["content_sid"].blank?
      errors << "invalid_content_sid" if data["content_sid"].present? && !data["content_sid"].match?(/\AHX[0-9a-fA-F]{32}\z/)
      errors.concat((names - semantic.keys).map { |name| "missing_variable:#{name}" })
      errors.concat((semantic.keys - names).map { |name| "extra_variable:#{name}" })
      errors.concat(names.filter_map { |name| "empty_variable:#{name}" if semantic[name].blank? })
      errors << "invalid_variable_numbering" unless numbered.keys == expected_numbers
      errors << "numbered_values_do_not_match_contract" unless numbered.values == names.map { |name| semantic[name] }
      JSON.generate(numbered)
    rescue JSON::GeneratorError => error
      errors ||= []
      errors << "invalid_json:#{error.message}"
    ensure
      debug = {
        template_key: data&.dig("key"), locale: data&.dig("locale"), content_sid: data&.dig("content_sid"),
        expected_variable_names: names || [], expected_variable_numbers: expected_numbers || [],
        received_variable_names: semantic&.keys || [], received_variable_numbers: numbered&.keys || []
      }
      return Result.new(errors.empty?, errors, debug)
    end
  end
end
