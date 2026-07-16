require "test_helper"

class MessagingWhatsappTemplateValidatorTest < ActiveSupport::TestCase
  class CountingProvider
    attr_reader :calls
    def initialize = @calls = 0
    def configured? = true
    def deliver(**)
      @calls += 1
      { provider: "twilio_whatsapp", external_id: "SM-test", status: "queued" }
    end
  end
  def setup
    @validator = Messaging::WhatsappTemplateValidator.new
  end

  test "accepts a complete semantic contract with contiguous numbering" do
    result = @validator.call(template(
      names: %i[client_name session_name],
      semantic: { client_name: "Ana", session_name: "Therapy" },
      numbered: { "1" => "Ana", "2" => "Therapy" }
    ))
    assert result.valid?
    assert_equal %w[1 2], result.debug[:expected_variable_numbers]
  end

  test "rejects missing extra empty and incorrectly numbered variables" do
    result = @validator.call(template(
      names: %i[client_name session_name],
      semantic: { client_name: "", unexpected: "value" },
      numbered: { "2" => "" }
    ))
    refute result.valid?
    assert_includes result.errors, "missing_variable:session_name"
    assert_includes result.errors, "extra_variable:unexpected"
    assert_includes result.errors, "empty_variable:client_name"
    assert_includes result.errors, "invalid_variable_numbering"
  end

  test "rejects unsupported locale and absent ContentSid" do
    result = @validator.call(template(locale: :pt, sid: nil))
    assert_includes result.errors, "unsupported_locale"
    assert_includes result.errors, "missing_content_sid"
  end

  test "classifies Twilio 21656 as a non retryable configuration error" do
    error = Messaging::TwilioWhatsappProvider::DeliveryError.new("invalid variables", provider_metadata: { error_code: "21656" })
    result = Ai::ErrorClassifier.call(error)
    assert_equal "provider_configuration", result.category
    assert_equal "failed_configuration", result.delivery_status
    refute result.retryable
  end

  test "classifies temporary and permanent provider failures" do
    temporary = Messaging::TwilioWhatsappProvider::DeliveryError.new("unavailable", provider_metadata: { http_status: 503 })
    permanent = Messaging::TwilioWhatsappProvider::DeliveryError.new("bad recipient", provider_metadata: { error_code: "21211", http_status: 400 })
    assert Ai::ErrorClassifier.call(temporary).retryable
    assert_equal "provider_temporary", Ai::ErrorClassifier.call(temporary).category
    refute Ai::ErrorClassifier.call(permanent).retryable
    assert_equal "provider_permanent", Ai::ErrorClassifier.call(permanent).category
  end

  test "does not call Twilio when local template validation fails" do
    user = User.create!(name: "Template Pro", email: "template-#{SecureRandom.hex(3)}@example.com", password: "password123")
    client = user.clients.create!(name: "Client", phone: "+59899111222")
    task = user.ai_tasks.create!(client: client, trigger_event: "before_session", automation_key: "confirm_session", scheduled_for: Time.current)
    provider = CountingProvider.new
    invalid = template(names: %i[client_name session_name], semantic: { client_name: "Client" }, numbered: { "1" => "Client" }).to_h

    assert_raises Messaging::Dispatcher::TemplateValidationError do
      Messaging::Dispatcher.new(provider: provider).deliver(user: user, client: client, body: "Confirm?", ai_task: task, metadata: { whatsapp_template: invalid })
    end

    assert_equal 0, provider.calls
    assert_equal "failed_configuration", task.reload.delivery_status
    assert_equal %w[client_name session_name], task.delivery_attempts.last.response_data["expected_variable_names"]
  end

  private

  def template(names: [:client_name], semantic: { client_name: "Ana" }, numbered: { "1" => "Ana" }, locale: :es, sid: "HX#{'a' * 32}")
    Messaging::WhatsappTemplateCatalog::Template.new(:session_confirmation, locale, sid, names, semantic, numbered)
  end
end
