class AiAlert < ApplicationRecord
  belongs_to :user
  belongs_to :client, optional: true
  belongs_to :session, optional: true
  belongs_to :ai_task, optional: true

  enum status: {
    open: "open",
    resolved: "resolved"
  }, _prefix: true

  enum severity: {
    low: "low",
    medium: "medium",
    high: "high"
  }, _prefix: true

  before_validation :normalize_metadata

  validates :title, :body, :status, :severity, presence: true
  validate :client_belongs_to_user
  validate :session_belongs_to_user

  scope :recent_first, -> { order(created_at: :desc) }

  private

  def normalize_metadata
    self.metadata = (metadata || {}).deep_stringify_keys
  end

  def client_belongs_to_user
    return if client.blank? || user.blank?

    errors.add(:client, "must belong to your account") unless client.user_id == user_id
  end

  def session_belongs_to_user
    return if session.blank? || user.blank?

    errors.add(:session, "must belong to your account") unless session.user_id == user_id
  end
end
