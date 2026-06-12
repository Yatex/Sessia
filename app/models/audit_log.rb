class AuditLog < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  validates :event, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def self.record!(user:, event:, actor: nil, auditable: nil, metadata: {})
    create!(
      user: user,
      actor: actor,
      auditable: auditable,
      event: event,
      metadata: metadata.compact
    )
  end
end
