class Client < ApplicationRecord
  WHATSAPP_CHANNEL = "whatsapp"
  CONTACT_CHANNELS = [WHATSAPP_CHANNEL].freeze

  has_secure_token :portal_token

  belongs_to :user
  has_many :sessions, dependent: :restrict_with_error
  has_many :payment_records, dependent: :nullify
  has_many :messages, dependent: :nullify
  has_many :ai_tasks, dependent: :nullify
  has_many :ai_alerts, dependent: :nullify

  enum status: {
    active: 0,
    inactive: 1
  }

  before_validation :normalize_email
  before_validation :normalize_phone
  before_validation :force_whatsapp_channel

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, allow_blank: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, presence: true, length: { maximum: 40 }
  validates :phone_normalized, presence: true
  validates :preferred_contact_channel, inclusion: { in: CONTACT_CHANNELS }

  scope :alphabetical, -> { order(Arel.sql("LOWER(name) ASC")) }

  def display_contact
    "WhatsApp #{phone}"
  end

  def linked?
    linked_at.present?
  end

  def mark_linked!
    update_column(:linked_at, Time.current) unless linked?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def normalize_phone
    self.phone = phone.to_s.strip
    self.phone_normalized = Messaging::WhatsappAddress.normalize(phone)
  end

  def force_whatsapp_channel
    self.preferred_contact_channel = WHATSAPP_CHANNEL
  end
end
