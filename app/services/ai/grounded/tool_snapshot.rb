module Ai
  module Grounded
    class ToolSnapshot
      attr_reader :results, :evidence, :executed_tools, :errors

      def initialize(metadata)
        metadata = metadata.to_h.deep_stringify_keys
        @results = metadata["tool_results"].to_h
        @executed_tools = Array(metadata["tools_completed"])
        @errors = Array(metadata["tool_errors"])
        @evidence = EvidenceSet.new
        Array(metadata["evidence"]).each do |item|
          item = item.deep_stringify_keys
          evidence.add_virtual(
            id: item.fetch("evidence_id"), source_type: item.fetch("source_type"),
            field: item.fetch("field"), value: item["value"], metadata: item["metadata"] || {}
          )
        end
      end
    end
  end
end
