class AiSetting < ApplicationRecord
  belongs_to :user

  FEATURE_FIELDS = [
    :confirm_sessions,
    :send_pre_session_reminders,
    :follow_up_no_response,
    :ask_feedback_after_sessions,
    :answer_basic_questions,
    :escalate_important_conversations,
    :payment_reminders
  ].freeze

  before_validation :normalize_professional_whatsapp_phone

  validates :user_id, uniqueness: true
  validates :professional_whatsapp_phone, length: { maximum: 40 }, allow_blank: true
  validates :professional_whatsapp_phone, presence: true, if: :use_professional_whatsapp?

  private

  def normalize_professional_whatsapp_phone
    self.professional_whatsapp_phone = professional_whatsapp_phone.to_s.strip.presence
  end
end
