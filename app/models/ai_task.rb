class AiTask < ApplicationRecord
  TRIGGER_EVENTS = %w[
    before_session
    no_response_window_reached
    after_session
    client_replied
    payment_due
    schedule_blocked
  ].freeze

  belongs_to :user
  belongs_to :client, optional: true
  belongs_to :session, optional: true
  has_many :messages, dependent: :nullify
  has_many :ai_alerts, dependent: :nullify

  enum status: {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed",
    skipped: "skipped"
  }, _prefix: true

  before_validation :set_defaults
  before_validation :normalize_json_columns

  validates :trigger_event, presence: true, inclusion: { in: TRIGGER_EVENTS }
  validates :status, :scheduled_for, presence: true
  validate :client_belongs_to_user
  validate :session_belongs_to_user

  scope :due, -> { where(status: "pending").where("scheduled_for <= ?", Time.current) }
  scope :recent_first, -> { order(created_at: :desc) }

  def activity_summary
    result_data["activity_summary"].presence ||
      result_data["reasoning_summary"].presence ||
      trigger_event.to_s.humanize
  end

  def decision_reason
    result_data["reasoning_summary"].presence ||
      result_data["error_message"].presence ||
      result_data.dig("failure_details", "error_message").presence ||
      error_message.presence
  end

  def performed_action_names
    Array(result_data["performed_actions"]).filter_map { |action| action["name"].presence }.presence ||
      Array(result_data["performed_action"]).compact_blank.presence ||
      ["do_nothing"]
  end

  def latest_outbound_message
    messages.outbound.max_by { |message| message.sent_at || message.created_at }
  end

  def message_delivery_summary
    latest_message = latest_outbound_message
    return "not_decided" if latest_message.blank? && (status_pending? || status_processing?)
    return "not_sent" if latest_message.blank?
    return "failed" if latest_message.failed?
    return "not_decided" if status_pending? || status_processing?
    return whatsapp_delivery_summary(latest_message) if latest_message.sent? && latest_message.channel == Client::WHATSAPP_CHANNEL
    return "accepted" if latest_message.queued?
    return "sent" if latest_message.sent?

    "not_sent"
  end

  def message_delivery_status_class
    case message_delivery_summary
    when "sent", "delivered", "read" then "delivered"
    when "accepted", "queued" then "accepted"
    when "failed" then "failed"
    when "not_decided" then "pending"
    else
      "neutral"
    end
  end

  private

  def whatsapp_delivery_summary(message)
    case message.metadata.to_h.dig("provider", "status").to_s
    when "delivered", "read"
      message.metadata.dig("provider", "status")
    when "failed", "undelivered"
      "failed"
    when "queued", "accepted", "sent", "sending"
      "accepted"
    else
      "sent"
    end
  end

  def set_defaults
    self.status = "pending" if status.blank?
    self.scheduled_for ||= Time.current
  end

  def normalize_json_columns
    self.context_data = (context_data || {}).deep_stringify_keys
    self.result_data = (result_data || {}).deep_stringify_keys
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
