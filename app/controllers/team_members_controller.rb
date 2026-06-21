class TeamMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_studio!
  before_action :set_team_member, only: %i[edit update]

  def index
    @team_members = current_user.studio_teachers.order(Arel.sql("LOWER(name) ASC"))
  end

  def new
    @team_member = current_user.studio_teachers.new(
      account_type: "professional",
      time_zone: current_user.time_zone,
      locale: current_user.locale
    )
  end

  def create
    @team_member = current_user.studio_teachers.new(team_member_params)
    @team_member.account_type = "professional"
    @team_member.locale = current_user.locale if @team_member.locale.blank?
    @team_member.time_zone = current_user.time_zone if @team_member.time_zone.blank?

    if @team_member.save
      redirect_to team_members_path, notice: "Professor added to the studio."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @team_member.update(team_member_update_params)
      redirect_to team_members_path, notice: "Professor updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def require_studio!
    return if current_user.studio?

    redirect_to dashboard_path, alert: "Only studio accounts can manage a team."
  end

  def set_team_member
    @team_member = current_user.studio_teachers.find(params[:id])
  end

  def team_member_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :time_zone, :locale)
  end

  def team_member_update_params
    permitted = params.require(:user).permit(:name, :email, :time_zone, :locale, :password, :password_confirmation)
    if permitted[:password].blank?
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end
    permitted
  end
end
