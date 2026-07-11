class Api::V1::Accounts::Crm::OpportunitiesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_opportunity, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 15

  def index
    @opportunities_scope = filtered_opportunities
    @opportunities_count = @opportunities_scope.count
    @opportunities = @opportunities_scope
                     .order(updated_at: :desc)
                     .page(permitted_params[:page] || 1)
                     .per((params[:per_page] || RESULTS_PER_PAGE).to_i.clamp(1, 100))
  end

  def show; end

  def create
    @opportunity = Current.account.crm_opportunities.create!(opportunity_params.merge(owner_id: opportunity_params[:owner_id] || current_user.id))
  end

  def update
    @opportunity.update!(opportunity_params)
  end

  def destroy
    @opportunity.destroy!
    head :ok
  end

  private

  def fetch_opportunity
    @opportunity = Current.account.crm_opportunities.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Opportunity)
  end

  # 支持视图筛选：我的商机、商机推进（排除终态）、按阶段（漏斗列）、按客户。
  def filtered_opportunities
    scope = Current.account.crm_opportunities
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.open_stages if params[:filter] == 'open'
    scope = scope.where(sales_stage: params[:sales_stage]) if params[:sales_stage].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope
  end

  def opportunity_params
    params.require(:opportunity).permit(
      :name, :crm_customer_id, :owner_id, :amount_micros, :currency,
      :sales_stage, :probability, :expected_close_date, :current_need,
      :competitor, :loss_reason, :next_action, :last_activity_at, :opportunity_remark
    )
  end

  def permitted_params
    params.permit(:page, :filter, :sales_stage, :customer_id)
  end
end
