module Ai
  module Grounded
    class EvidenceSet
      def initialize
        @items = {}
      end

      def add(source:, field:, value:, metadata: {})
        return if value.nil?

        id = "#{source.class.model_name.singular}.#{source.id}.#{field}"
        items[id] = {
          "evidence_id" => id,
          "source_type" => source.class.model_name.singular,
          "source_id" => source.id.to_s,
          "field" => field.to_s,
          "value" => serialize(value),
          "metadata" => metadata.deep_stringify_keys
        }
        id
      end

      def add_virtual(id:, source_type:, field:, value:, metadata: {})
        items[id] = {
          "evidence_id" => id,
          "source_type" => source_type,
          "field" => field.to_s,
          "value" => serialize(value),
          "metadata" => metadata.deep_stringify_keys
        }
        id
      end

      def include?(id)
        items.key?(id.to_s)
      end

      def fetch(id)
        items.fetch(id.to_s)
      end

      def values
        items.values
      end

      private

      attr_reader :items

      def serialize(value)
        case value
        when Time, ActiveSupport::TimeWithZone then value.iso8601
        when Date then value.iso8601
        when Hash then value.deep_stringify_keys
        when Array then value.map { |item| serialize(item) }
        else value
        end
      end
    end
  end
end
