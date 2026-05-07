# frozen_string_literal: true

if defined?(Resend)
  Resend.configure do |config|
    config.api_key = ENV["RESEND_API_KEY"]
  end
end
