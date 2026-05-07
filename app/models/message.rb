class Message < ApplicationRecord
  belongs_to :user
  belongs_to :client, optional: true
  belongs_to :session, optional: true
  belongs_to :ai_task, optional: true

  enum direction: {
    outbound: 0,
    inbound: 1,
    internal_note: 2
  }

  enum status: {
    draft: 0,
    queued: 1,
    sent: 2,
    failed: 3
  }

  validates :channel, presence: true
  validates :body, presence: true, if: :inbound?
  before_validation :normalize_metadata
  validate :client_belongs_to_user
  validate :session_belongs_to_user

  scope :recent_first, -> { order(created_at: :desc) }

  private

  def client_belongs_to_user
    return if client.blank? || user.blank?

    errors.add(:client, "must belong to your account") unless client.user_id == user_id
  end

  def session_belongs_to_user
    return if session.blank? || user.blank?

    errors.add(:session, "must belong to your account") unless session.user_id == user_id
  end

  def normalize_metadata
    self.metadata = (metadata || {}).deep_stringify_keys if has_attribute?(:metadata)
  end
end
