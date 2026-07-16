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

  enum account_type: {
    professional: 0,
    studio: 1
  }

  belongs_to :studio_owner, class_name: "User", foreign_key: :studio_id, optional: true, inverse_of: :studio_teachers
  has_many :studio_teachers, class_name: "User", foreign_key: :studio_id, dependent: :nullify, inverse_of: :studio_owner

  has_many :clients, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :payment_records, dependent: :destroy
  has_many :payment_accounts, dependent: :destroy
  has_many :charges, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :client_billing_profiles, dependent: :destroy
  has_many :credit_ledger_entries, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :ai_tasks, dependent: :destroy
  has_many :ai_traces, dependent: :destroy
  has_many :ai_alerts, dependent: :destroy
  has_many :availability_rules, dependent: :destroy
  has_many :schedule_blocks, dependent: :destroy
  has_one :ai_setting, dependent: :destroy
  has_one :calendar_connection, dependent: :destroy

  def mercado_pago_account
    payment_accounts.find_by(provider: PaymentAccount::PROVIDER_MERCADO_PAGO)
  end

  before_validation :normalize_email
  before_validation :normalize_time_zone
  before_validation :normalize_locale
  after_create :create_default_ai_setting
  after_create :create_default_availability_rules
  after_create :create_free_trial_subscription

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :google_uid, uniqueness: true, allow_blank: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :time_zone, presence: true
  validates :locale, presence: true, inclusion: { in: AVAILABLE_LOCALES.keys }
  validates :payment_instructions, length: { maximum: 1_500 }, allow_blank: true
  validate :studio_relationship_is_valid
  validate :time_zone_is_supported

  scope :admins, -> { where(role: :admin) }
  scope :professionals, -> { where(account_type: :professional) }
  scope :studios, -> { where(account_type: :studio) }

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

  def workspace_user_ids
    return [id] unless studio?

    [id] + studio_teachers.select(:id).map(&:id)
  end

  def workspace_professionals
    return User.where(id: id) unless studio?

    User.where(id: workspace_user_ids).order(Arel.sql("LOWER(name) ASC"))
  end

  def studio_member?
    studio_id.present?
  end

  def account_type_label
    studio? ? "Studio" : "Independent professional"
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

  def studio_relationship_is_valid
    return if studio_id.blank?

    errors.add(:studio_owner, "must be a studio account") unless studio_owner&.studio?
    errors.add(:studio_owner, "cannot be assigned to a studio") if studio?
  end

  def create_default_ai_setting
    create_ai_setting! unless ai_setting
  end

  def create_default_availability_rules
    Availability::Defaults.ensure_for(self)
  end

  def create_free_trial_subscription
    Subscription.create_free_trial_for!(self)
  end

  def digest_token(token)
    self.class.digest_token(token)
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end
end
