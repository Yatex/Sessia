module Messaging
  class WhatsappTemplateManager
    def initialize(catalog: Messaging::WhatsappTemplateCatalog, client: Messaging::TwilioContentClient.new)
      @catalog, @client = catalog, client
    end

    def dry_run
      definitions.map { |definition| base_row(definition).merge(status: "dry_run", errors: local_errors(definition)) }
    end

    def create
      existing = client.contents.index_by { |content| [content["friendly_name"], content["language"]] }
      definitions.map do |definition|
        errors = local_errors(definition)
        next base_row(definition).merge(status: "invalid", content_sid: nil, errors: errors) if errors.any?

        remote = existing[[definition.friendly_name, definition.locale.to_s]]
        if remote
          base_row(definition).merge(status: "exists", content_sid: remote["sid"], errors: [])
        else
          created = client.create(definition)
          base_row(definition).merge(status: "created", content_sid: created["sid"], errors: [])
        end
      rescue StandardError => error
        base_row(definition).merge(status: "error", content_sid: nil, errors: [error.message])
      end
    rescue StandardError => error
      definitions.map { |definition| base_row(definition).merge(status: "error", content_sid: nil, errors: [error.message]) }
    end

    def status
      definitions.map do |definition|
        errors = local_errors(definition)
        sid = definition.content_sid
        if sid.blank?
          errors << "missing_env:#{definition.env_key}"
          next base_row(definition).merge(status: "missing_env", content_sid: nil, errors: errors)
        end
        unless sid.match?(/\AHX[0-9a-fA-F]{32}\z/)
          errors << "invalid_content_sid:#{definition.env_key}"
          next base_row(definition).merge(status: "invalid", content_sid: sid, errors: errors)
        end

        remote = client.fetch(sid)
        approval = client.approval_status(sid)
        whatsapp = approval["whatsapp"].to_h
        base_row(definition).merge(
          status: whatsapp["status"].presence || "unsubmitted",
          content_sid: sid,
          errors: errors + [whatsapp["rejection_reason"].presence].compact,
          remote: remote,
          approval: whatsapp
        )
      rescue StandardError => error
        base_row(definition).merge(status: "error", content_sid: sid, errors: [error.message])
      end
    end

    def audit
      definitions.map do |definition|
        errors = local_errors(definition)
        sid = definition.content_sid
        if sid.blank?
          errors << "missing_env:#{definition.env_key}"
          next base_row(definition).merge(status: "invalid", content_sid: nil, errors: errors)
        end
        unless sid.match?(/\AHX[0-9a-fA-F]{32}\z/)
          errors << "invalid_content_sid:#{definition.env_key}"
          next base_row(definition).merge(status: "invalid", content_sid: sid, errors: errors)
        end

        remote = client.fetch(sid)
        errors.concat(remote_errors(definition, remote))
        base_row(definition).merge(status: errors.empty? ? "ok" : "invalid", content_sid: sid, errors: errors, remote: remote)
      rescue StandardError => error
        base_row(definition).merge(status: "error", content_sid: sid, errors: errors + [error.message])
      end
    end

    def env_block(rows = nil)
      sids = Array(rows).filter_map do |row|
        next if row[:content_sid].blank?
        [[row[:key], row[:locale]], row[:content_sid]]
      end.to_h
      catalog.env_block(sids)
    end

    private

    attr_reader :catalog, :client
    def definitions = catalog.definitions

    def base_row(definition)
      definition.to_h.except(:content_sid).merge(content_sid: definition.content_sid)
    end

    def local_errors(definition)
      errors = []
      errors << "invalid_placeholder_sequence" unless definition.placeholder_numbers == definition.expected_numbers
      errors << "duplicate_variables" unless definition.variables.uniq.length == definition.variables.length
      errors << "invalid_category" unless definition.category.in?(%w[UTILITY MARKETING AUTHENTICATION])
      errors << "invalid_friendly_name" unless definition.friendly_name.match?(/\A[a-z0-9_]+\z/)
      begin
        definition.default_variables
      rescue KeyError
        errors << "unknown_variables"
      end
      errors
    end

    def remote_errors(definition, remote)
      errors = []
      remote_body = remote.dig("types", "twilio/text", "body").to_s
      errors << "friendly_name_mismatch" unless remote["friendly_name"] == definition.friendly_name
      errors << "locale_mismatch" unless remote["language"] == definition.locale.to_s
      errors << "body_mismatch" unless remote_body == definition.body
      errors << "placeholder_mismatch" unless remote_body.scan(/\{\{(\d+)\}\}/).flatten == definition.expected_numbers
      errors << "variable_numbers_mismatch" unless remote["variables"].to_h.keys == definition.expected_numbers
      errors
    end
  end
end
