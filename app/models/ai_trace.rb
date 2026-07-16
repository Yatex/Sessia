class AiTrace < ApplicationRecord
  belongs_to :ai_task
  belongs_to :user
  belongs_to :client, optional: true
  belongs_to :session, optional: true

  validates :trace_id, presence: true, uniqueness: true

  before_validation :normalize_json_columns

  private

  def normalize_json_columns
    %i[context_scope validation_results candidate_decision final_decision execution_result delivery_result].each do |attribute|
      public_send("#{attribute}=", (public_send(attribute) || {}).deep_stringify_keys)
    end
    %i[allowed_actions tools_requested tools_completed tool_errors evidence_found evidence_used].each do |attribute|
      public_send("#{attribute}=", Array(public_send(attribute)))
    end
  end
end
