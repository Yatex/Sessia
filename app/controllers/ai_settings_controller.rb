class AiSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    @ai_setting = current_user.ai_setting || current_user.create_ai_setting!
    load_activity
  end

  def update
    @ai_setting = current_user.ai_setting || current_user.create_ai_setting!

    if @ai_setting.update(ai_setting_params)
      redirect_to ai_assistant_path, notice: "AI assistant settings updated."
    else
      load_activity
      render :show, status: :unprocessable_entity
    end
  end

  def run
    result = Ai::ManagerLoopService.new(users: [current_user]).call
    flash_type = result.failed_count.positive? ? :alert : :notice
    redirect_to ai_assistant_path, flash: { flash_type => "AI assistant run: #{result.summary}" }
  end

  private

  def load_activity
    @recent_ai_tasks = current_user.ai_tasks.includes(:client, :session).recent_first.limit(12)
    @ai_alerts = current_user.ai_alerts.includes(:client, :session).where(status: "open").recent_first.limit(8)
  end

  def ai_setting_params
    params.require(:ai_setting).permit(
      *AiSetting::FEATURE_FIELDS,
      :use_professional_whatsapp,
      :professional_whatsapp_phone,
      :instructions
    )
  end
end
