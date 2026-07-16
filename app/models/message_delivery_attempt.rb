class MessageDeliveryAttempt < ApplicationRecord
  belongs_to :message
  belongs_to :ai_task, optional: true

  STATUSES = %w[pending sent delivered failed].freeze

  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  validates :attempt_number, uniqueness: { scope: :message_id }
  validates :status, inclusion: { in: STATUSES }

  scope :due_retry, -> { where(retryable: true).where("next_retry_at <= ?", Time.current) }
end
