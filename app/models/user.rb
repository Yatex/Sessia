class User < ApplicationRecord
  DEFAULT_TIME_ZONE = "UTC"
  DEFAULT_LOCALE = "en"
  AVAILABLE_LOCALES = {
    "en" => "English",
    "es" => "Español"
  }.freeze

  has_secure_password

  enum role: {
    member: 0,
    admin: 1
  }

  has_many :clients, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :payment_records, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :ai_tasks, dependent: :destroy
  has_many :ai_alerts, dependent: :destroy
  has_many :availability_rules, dependent: :destroy
  has_many :schedule_blocks, dependent: :destroy
  has_one :ai_setting, dependent: :destroy
  has_one :calendar_connection, dependent: :destroy

  before_validation :normalize_email
  before_validation :normalize_time_zone
  before_validation :normalize_locale
  after_create :create_default_ai_setting
  after_create :create_default_availability_rules

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :google_uid, uniqueness: true, allow_blank: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :time_zone, presence: true
  validates :locale, presence: true, inclusion: { in: AVAILABLE_LOCALES.keys }
  validate :time_zone_is_supported

  scope :admins, -> { where(role: :admin) }

  def self.find_by_normalized_email(email)
    find_by(email: email.to_s.strip.downcase)
  end

  def generate_password_reset_token!
    token = SecureRandom.urlsafe_base64(32)
    update!(
      password_reset_token_digest: digest_token(token),
      password_reset_sent_at: Time.current
    )
    token
  end

  def clear_password_reset_token!
    update!(password_reset_token_digest: nil, password_reset_sent_at: nil)
  end

  def password_reset_token_valid?
    password_reset_sent_at.present? && password_reset_sent_at > 2.hours.ago
  end

  def subscribed?
    subscriptions.active_or_trialing.exists?
  end

  def current_subscription
    subscriptions.order(created_at: :desc).detect(&:usable?)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def normalize_time_zone
    zone = ActiveSupport::TimeZone[time_zone.to_s]
    self.time_zone = zone&.tzinfo&.identifier || DEFAULT_TIME_ZONE
  end

  def normalize_locale
    normalized = locale.to_s.strip.downcase.tr("_", "-").split("-").first
    self.locale = AVAILABLE_LOCALES.key?(normalized) ? normalized : DEFAULT_LOCALE
  end

  def time_zone_is_supported
    errors.add(:time_zone, "is not supported") unless ActiveSupport::TimeZone[time_zone].present?
  end

  def create_default_ai_setting
    create_ai_setting! unless ai_setting
  end

  def create_default_availability_rules
    Availability::Defaults.ensure_for(self)
  end

  def digest_token(token)
    self.class.digest_token(token)
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end
end
