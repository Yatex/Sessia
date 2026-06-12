class PaymentAccount < ApplicationRecord
  PROVIDER_MERCADO_PAGO = "mercado_pago"

  belongs_to :user

  enum status: {
    disconnected: 0,
    connected: 1,
    expired: 2,
    error: 3
  }

  before_validation :normalize_provider

  validates :provider, presence: true, inclusion: { in: [PROVIDER_MERCADO_PAGO] }
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

  def token_expired?
    access_token.blank? || token_expires_at.blank? || token_expires_at <= 5.minutes.from_now
  end

  def mark_connected!(attributes = {})
    assign_attributes(attributes)
    self.status = :connected
    self.connected_at ||= Time.current
    self.last_error = nil
    save!
  end

  def mark_disconnected!
    update!(
      status: :disconnected,
      provider_user_id: nil,
      access_token_ciphertext: nil,
      refresh_token_ciphertext: nil,
      token_expires_at: nil,
      last_error: nil
    )
  end

  private

  def normalize_provider
    self.provider = provider.to_s.presence || PROVIDER_MERCADO_PAGO
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
    key = Rails.application.key_generator.generate_key("sessia/mercado-pago/token/v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end
end
