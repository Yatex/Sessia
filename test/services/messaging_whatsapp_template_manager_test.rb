require "test_helper"
require "rake"

class MessagingWhatsappTemplateManagerTest < ActiveSupport::TestCase
  test "catalog adopts the four existing confirmation and reminder templates" do
    expected = {
      [:session_confirmation, :es] => [
        "copy_of_sessia_session_confirmation_es_v1",
        "Hola {{1}}, ¿podés confirmar tu sesión de {{2}} del {{3}} a las {{4}}? Cualquier otra consulta puedes hacerla aqui"
      ],
      [:session_confirmation, :en] => [
        "copy_of_sessia_session_confirmation_en_v1",
        "Hi {{1}}, can you confirm your {{2}} session on {{3}} at {{4}}? Any other questions can be answered here"
      ],
      [:session_reminder, :es] => [
        "copy_of_sessia_session_reminder_es_v1",
        "Hola {{1}}, te recordamos tu sesión de {{2}} del {{3}} a las {{4}}. Cualquier pregunta puedes hacerla aqui."
      ],
      [:session_reminder, :en] => [
        "copy_of_sessia_session_reminder_en_v1",
        "Hi {{1}}, this is a reminder for your {{2}} session on {{3}} at {{4}}. See you soon"
      ]
    }

    expected.each do |(key, locale), (friendly_name, body)|
      definition = Messaging::WhatsappTemplateCatalog.fetch(key, locale)
      assert_equal friendly_name, definition.friendly_name
      assert_equal body, definition.body
    end
  end

  class FakeClient
    attr_reader :calls, :created

    def initialize(contents: [], remotes: {}, approvals: {})
      @contents, @remotes, @approvals = contents, remotes, approvals
      @calls, @created = [], []
    end

    def contents
      calls << :contents
      @contents
    end

    def create(definition)
      calls << [:create, definition.friendly_name]
      created << definition
      { "sid" => "HX#{created.length.to_s.rjust(32, '0')}" }
    end

    def fetch(sid)
      calls << [:fetch, sid]
      @remotes.fetch(sid)
    end

    def approval_status(sid)
      calls << [:approval_status, sid]
      @approvals.fetch(sid, { "whatsapp" => { "status" => "approved", "rejection_reason" => "" } })
    end
  end

  def setup
    @original_env = Messaging::WhatsappTemplateCatalog.definitions.to_h { |definition| [definition.env_key, ENV[definition.env_key]] }
    @original_env.each_key { |key| ENV.delete(key) }
  end

  def teardown
    @original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "dry run lists every catalog contract without calling Twilio" do
    client = FakeClient.new
    rows = manager(client).dry_run

    assert_equal 14, rows.length
    assert_empty client.calls
    assert rows.all? { |row| row[:status] == "dry_run" }
    assert_equal %w[1 2 3 4], rows.first[:placeholders]
  end

  test "rake dry run prints bodies variables placeholders and ENV without API credentials" do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    task = Rake::Task["sessia:twilio:templates:dry_run"]
    task.reenable

    output = capture_io { task.invoke }.first

    assert_includes output, "session_confirmation/es"
    assert_includes output, "body:"
    assert_includes output, "{{1}}, {{2}}, {{3}}, {{4}}"
    assert_includes output, "TWILIO_TEMPLATE_SESSION_CONFIRMATION_ES"
  end

  test "create keeps existing remote templates and creates only missing definitions" do
    existing_definition = Messaging::WhatsappTemplateCatalog.definitions.first
    client = FakeClient.new(contents: [{
      "friendly_name" => existing_definition.friendly_name,
      "language" => existing_definition.locale.to_s,
      "sid" => "HX#{'9' * 32}"
    }])

    rows = manager(client).create

    assert_equal "exists", rows.first[:status]
    assert_equal 13, client.created.length
    assert_equal 13, rows.count { |row| row[:status] == "created" }
  end

  test "audit reports missing ENV without making remote requests" do
    client = FakeClient.new
    rows = manager(client).audit

    assert rows.all? { |row| row[:status] == "invalid" }
    assert rows.all? { |row| row[:errors].any? { |error| error.start_with?("missing_env:") } }
    assert_empty client.calls
  end

  test "audit compares remote body locale name and variable numbering" do
    definition = Messaging::WhatsappTemplateCatalog.definitions.first
    sid = "HX#{'3' * 32}"
    ENV[definition.env_key] = sid
    remote = {
      "friendly_name" => "old_template",
      "language" => "en",
      "variables" => { "1" => "one" },
      "types" => { "twilio/text" => { "body" => "Old body {{1}}" } }
    }

    row = manager(FakeClient.new(remotes: { sid => remote })).audit.first

    assert_equal "invalid", row[:status]
    assert_includes row[:errors], "friendly_name_mismatch"
    assert_includes row[:errors], "locale_mismatch"
    assert_includes row[:errors], "body_mismatch"
    assert_includes row[:errors], "placeholder_mismatch"
    assert_includes row[:errors], "variable_numbers_mismatch"
  end

  test "audit rejects an invalid local variable contract" do
    invalid = Messaging::WhatsappTemplateCatalog::Definition.new(
      :broken, :es, "sessia_broken_es_v1", "UTILITY", "Hola {{2}}", [:client_name],
      "TWILIO_TEMPLATE_BROKEN_ES", "test"
    )
    catalog = Class.new do
      define_singleton_method(:definitions) { [invalid] }
      define_singleton_method(:env_block) { |_sids = {}| "" }
    end

    row = Messaging::WhatsappTemplateManager.new(catalog: catalog, client: FakeClient.new).audit.first
    assert_includes row[:errors], "invalid_placeholder_sequence"
  end

  test "create refuses an invalid local variable contract before an API create call" do
    invalid = Messaging::WhatsappTemplateCatalog::Definition.new(
      :broken, :es, "sessia_broken_es_v1", "UTILITY", "Hola {{2}}", [:client_name],
      "TWILIO_TEMPLATE_BROKEN_ES", "test"
    )
    catalog = Class.new do
      define_singleton_method(:definitions) { [invalid] }
      define_singleton_method(:env_block) { |_sids = {}| "" }
    end
    client = FakeClient.new

    row = Messaging::WhatsappTemplateManager.new(catalog: catalog, client: client).create.first

    assert_equal "invalid", row[:status]
    assert_empty client.created
  end

  test "audit identifies unknown semantic variables" do
    invalid = Messaging::WhatsappTemplateCatalog::Definition.new(
      :broken, :es, "sessia_broken_es_v1", "UTILITY", "Hola {{1}}", [:unknown_value],
      "TWILIO_TEMPLATE_BROKEN_ES", "test"
    )
    catalog = Class.new do
      define_singleton_method(:definitions) { [invalid] }
      define_singleton_method(:env_block) { |_sids = {}| "" }
    end

    row = Messaging::WhatsappTemplateManager.new(catalog: catalog, client: FakeClient.new).audit.first
    assert_includes row[:errors], "unknown_variables"
  end

  test "audit rejects malformed ContentSid ENV without calling Twilio" do
    definition = Messaging::WhatsappTemplateCatalog.definitions.first
    ENV[definition.env_key] = "old-template-id"
    client = FakeClient.new

    row = manager(client).audit.first

    assert_includes row[:errors], "invalid_content_sid:#{definition.env_key}"
    assert_empty client.calls
  end

  test "ENV block is complete and never mutates ENV" do
    rows = manager(FakeClient.new).create
    block = manager(FakeClient.new).env_block(rows)

    assert_equal 14, block.lines.length
    assert_match(/TWILIO_TEMPLATE_SESSION_CONFIRMATION_ES=HX\d{32}/, block)
    assert_nil ENV["TWILIO_TEMPLATE_SESSION_CONFIRMATION_ES"]
  end

  test "status reports remote WhatsApp approval and rejection errors" do
    definition = Messaging::WhatsappTemplateCatalog.definitions.first
    sid = "HX#{'4' * 32}"
    ENV[definition.env_key] = sid
    client = FakeClient.new(
      remotes: { sid => remote_for(definition) },
      approvals: { sid => { "whatsapp" => { "status" => "rejected", "rejection_reason" => "Variable samples are unclear" } } }
    )

    row = manager(client).status.first
    assert_equal "rejected", row[:status]
    assert_equal ["Variable samples are unclear"], row[:errors]
  end

  private

  def manager(client) = Messaging::WhatsappTemplateManager.new(client: client)

  def remote_for(definition)
    {
      "friendly_name" => definition.friendly_name,
      "language" => definition.locale.to_s,
      "variables" => definition.default_variables,
      "types" => { "twilio/text" => { "body" => definition.body } }
    }
  end
end
