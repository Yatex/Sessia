# Loads local development environment variables without overriding values already
# provided by the shell.
#
# This keeps local `.env` support dependency-free and leaves production config
# under the real process environment.
module LocalEnv
  PROTECTED_KEYS = %w[RAILS_MASTER_KEY SECRET_KEY_BASE].freeze

  module_function

  def load!(path = File.expand_path("../.env", __dir__))
    return unless ENV.fetch("RAILS_ENV", "development") == "development"
    return unless File.file?(path)

    File.foreach(path) do |line|
      key, value = parse_line(line)
      next if empty?(key) || empty?(value) || protected_key?(key) || placeholder_value?(value) || ENV.key?(key)

      ENV[key] = value
    end
  end

  def parse_line(line)
    stripped = line.to_s.strip
    return [nil, nil] if stripped.empty? || stripped.start_with?("#")

    key, value = stripped.split("=", 2)
    return [nil, nil] if key.to_s.strip.empty? || value.nil?

    [key.strip, normalize_value(value)]
  end

  def normalize_value(value)
    normalized = value.to_s.strip
    if (normalized.start_with?('"') && normalized.end_with?('"')) ||
        (normalized.start_with?("'") && normalized.end_with?("'"))
      normalized = normalized[1...-1]
    end
    normalized
  end

  def empty?(value)
    value.nil? || value.to_s.empty?
  end

  def placeholder_value?(value)
    ["..."].include?(value.to_s.strip)
  end

  def protected_key?(key)
    PROTECTED_KEYS.include?(key.to_s)
  end
end

LocalEnv.load!
