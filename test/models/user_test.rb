require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "stores browser IANA time zone identifiers" do
    user = User.new(
      name: "Time Zone User",
      email: "timezone@example.com",
      password: "password123",
      time_zone: "America/New_York"
    )

    assert user.valid?
    assert_equal "America/New_York", user.time_zone
  end

  test "falls back to UTC for unsupported time zones" do
    user = User.new(
      name: "Fallback User",
      email: "fallback@example.com",
      password: "password123",
      time_zone: "Not/AZone"
    )

    assert user.valid?
    assert_equal "UTC", user.time_zone
  end

  test "normalizes supported language preferences" do
    user = User.new(
      name: "Spanish User",
      email: "spanish@example.com",
      password: "password123",
      locale: "es-UY"
    )

    assert user.valid?
    assert_equal "es", user.locale
  end

  test "falls back to English for unsupported language preferences" do
    user = User.new(
      name: "Fallback Locale User",
      email: "fallback-locale@example.com",
      password: "password123",
      locale: "pt-BR"
    )

    assert user.valid?
    assert_equal "en", user.locale
  end
end
