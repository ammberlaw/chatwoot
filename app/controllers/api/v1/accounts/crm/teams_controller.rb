class Api::V1::Accounts::Crm::TeamsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_team, only: [:show, :update, :destroy]

  # 团队列表：超级管理员/管理员看全部；部门主管与业务员仅看自己所属团队（筛选下拉同步收口）。
  def index
    @teams = visible_teams.order(:name)
  end

  def show; end

  def create
    @team = Current.account.crm_teams.create!(team_params)
  end

  def update
    @team.update!(team_params)
  end

  def destroy
    @team.destroy!
    head :ok
  end

  private

  def fetch_team
    @team = Current.account.crm_teams.find(params[:id])
  end

  def visible_teams
    return Current.account.crm_teams if Current.account_user.administrator? || Current.account_user.crm_deputy_admin?

    Current.account.crm_teams.where(id: Current.account_user.crm_team_id)
  end

  def check_authorization
    authorize(Crm::Team)
  end

  def team_params
    params.require(:team).permit(:name, :description, :team_lead_id)
  end
end
