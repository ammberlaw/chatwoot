class Api::V1::Accounts::Crm::TeamsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_team, only: [:show, :update, :destroy]

  def index
    @teams = Current.account.crm_teams.order(:name)
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

  def check_authorization
    authorize(Crm::Team)
  end

  def team_params
    params.require(:team).permit(:name, :description, :team_lead_id)
  end
end
