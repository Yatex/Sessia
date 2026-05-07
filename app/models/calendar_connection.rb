class CalendarConnection < ApplicationRecord
  PROVIDER_GOOGLE = "google"

  belongs_to :user

  enum status: {
    connected: 0,
    disconnected: 1,
    errored: 2
  }

  before_validation :normalize_provider
  before_validation :normalize_calendar_id

  validates :provider, presence: true, inclusion: { in: [PROVIDER_GOOGLE] }
  validates :calendar_id, presence: true
  validates :user_id, uniqueness: { scope: :provider }

  def access_token
    decrypt_token(access_token_ciphertext)
  end

  def access_token=(token)
    self.access_token_ciphertext = encrypt_token(token)
  end

  def refresh_token
    decrypt_token(refresh_token_ciphertext)
  end

  def refresh_token=(token)
    self.refresh_token_ciphertext = encrypt_token(token)
  end

  def access_token_expired?
    access_token.blank? || access_token_expires_at.blank? || access_token_expires_at <= 2.minutes.from_now
  end

  private

  def normalize_provider
    self.provider = provider.to_s.presence || PROVIDER_GOOGLE
  end

  def normalize_calendar_id
    self.calendar_id = calendar_id.to_s.presence || "primary"
  end

  def encrypt_token(token)
    return if token.blank?

    self.class.token_encryptor.encrypt_and_sign(token)
  end

  def decrypt_token(ciphertext)
    return if ciphertext.blank?

    self.class.token_encryptor.decrypt_and_verify(ciphertext)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def self.token_encryptor
    key = Rails.application.key_generator.generate_key("sessia/google-calendar/token/v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end
end
