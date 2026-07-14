class Api::V1::Accounts::Crm::OpportunitiesController < Api::V1::Accounts::Crm::BaseController
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

  # 按可见范围取商机：业务员只能查看/编辑/删除自己的，主管本团队，管理员全部。
  # 越权访问（如业务员删他人商机）会因不在范围内而 RecordNotFound → 404。
  def fetch_opportunity
    @opportunity = scope_by_owner(Current.account.crm_opportunities).find(params[:id])
  end

  def check_authorization
    authorize(Crm::Opportunity)
  end

  # 支持视图筛选：我的商机、商机推进（排除终态）、按阶段（漏斗列）、按客户；
  # admin 看板按团队/业务员：team_id 过滤该团队成员的商机，owner_id 精确到某业务员。
  def filtered_opportunities
    # 数据范围（按 CRM 角色）：管理员全部 / 主管团队 / 业务员本人。
    scope = scope_by_owner(view_scoped(Current.account.crm_opportunities))
    scope = scope.where(sales_stage: params[:sales_stage]) if params[:sales_stage].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope = scope.where(owner_id: filter_owner_ids) if filter_owner_ids
    scope
  end

  # 视图筛选：我的商机 / 商机推进（排除终态）。
  def view_scoped(scope)
    return scope.owned_by(current_user.id) if params[:filter] == 'mine'
    return scope.open_stages if params[:filter] == 'open'

    scope
  end

  # owner_id 优先；否则退到 team_id 的成员集合；均无则返回 nil（不按人过滤）。
  def filter_owner_ids
    return [params[:owner_id]] if params[:owner_id].present?
    return team_member_ids(params[:team_id]) if params[:team_id].present?

    nil
  end

  def team_member_ids(team_id)
    Current.account.crm_teams.find_by(id: team_id)&.members&.pluck(:id) || []
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
