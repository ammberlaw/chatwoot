class Api::V1::Accounts::Crm::OpportunitiesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_opportunity, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 15

  def index
    @opportunities_scope = filtered_opportunities
    @opportunities_count = @opportunities_scope.count
    @opportunities = @opportunities_scope
                     .order(order_clause)
                     .page(permitted_params[:page] || 1)
                     .per((params[:per_page] || RESULTS_PER_PAGE).to_i.clamp(1, 100))
  end

  def show; end

  def create
    @opportunity = Current.account.crm_opportunities.create!(opportunity_params.merge(owner_id: opportunity_params[:owner_id] || current_user.id))
    sync_follow_up_schedule
  end

  def update
    @opportunity.update!(opportunity_params)
    sync_follow_up_schedule
  end

  def destroy
    @opportunity.destroy!
    head :ok
  end

  # 认领公海商机：归入自己名下（公海商机对全员开放，不走 owner 范围）。
  def claim
    @opportunity = Current.account.crm_opportunities.find(params[:id])
    # 锁内复检仍在公海：两人同时认领同一公海商机时只有先拿锁的成功，杜绝静默抢单覆盖。
    claimed = false
    @opportunity.with_lock do
      next unless @opportunity.is_in_public_pool?

      @opportunity.update!(owner_id: current_user.id, is_in_public_pool: false, public_pool_at: nil)
      claimed = true
    end
    return render json: { message: '该商机已被他人认领' }, status: :forbidden unless claimed

    render :show
  end

  # 释放到商机公海：仅可释放自己数据范围内的商机。
  def release
    @opportunity = scope_by_team_owner(Current.account.crm_opportunities).find(params[:id])
    @opportunity.move_to_public_pool!
    render :show
  end

  private

  # 按可见范围取商机：业务员只能查看/编辑/删除自己的，主管本团队，管理员全部。
  # 越权访问（如业务员删他人商机）会因不在范围内而 RecordNotFound → 404。
  def fetch_opportunity
    @opportunity = scope_by_team_owner(Current.account.crm_opportunities).find(params[:id])
  end

  def check_authorization
    authorize(Crm::Opportunity)
  end

  # 支持视图筛选：我的商机、商机推进（排除终态）、按阶段（漏斗列）、按客户；
  # admin 看板按团队/业务员：team_id 过滤该团队成员的商机，owner_id 精确到某业务员。
  def filtered_opportunities
    scope = scoped_opportunities
    return scope if params[:q].blank?

    # 看板快速查找：按商机名或客户名模糊搜（覆盖常规看板与公海）。
    keyword = "%#{params[:q].strip}%"
    scope.left_joins(:crm_customer)
         .where('crm_opportunities.name ILIKE :q OR crm_customers.name ILIKE :q', q: keyword)
  end

  def scoped_opportunities
    # 商机公海：全员可见全公司的池子，不按 owner 过滤（与客户公海同口径）。
    return Current.account.crm_opportunities.in_public_pool if params[:filter] == 'public_pool'

    # 数据范围（按 CRM 角色）：管理员全部 / 主管团队 / 业务员本人。公海商机不混入常规视图。
    scope = scope_by_team_owner(view_scoped(Current.account.crm_opportunities.in_private_pool))
    scope = scope.where(sales_stage: params[:sales_stage]) if params[:sales_stage].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope = scope.where(owner_id: filter_owner_ids) if filter_owner_ids
    scope
  end

  # 排序：创建时间 / 金额 / 成交概率，正序倒序；默认按更新时间倒序。
  # 金额、概率可能为空，统一排到末尾。
  SORT_COLUMNS = { 'created_at' => 'created_at', 'amount' => 'amount_micros', 'probability' => 'probability' }.freeze

  def order_clause
    column = SORT_COLUMNS[params[:sort]]
    return { updated_at: :desc } unless column

    direction = params[:direction] == 'asc' ? 'ASC' : 'DESC'
    # 补 id 兜底：赢率是 10/20/50 这种档位、金额也常相同，并列行不唯一定序的话，
    # 翻页（一页一条 SQL）会让某条商机在任何一页都不出现。同客户列表 sort_clause 的写法。
    Arel.sql("#{column} #{direction} NULLS LAST, crm_opportunities.id DESC")
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

  # 商机「下次跟进时间」→ 同步一条个人日程提醒（幂等）：有时间即 upsert、清空即删除。
  # 看板拖拽等只改阶段的更新也会走到这里，但由于按当前已存的 next_follow_up_at 决策，
  # 不会误删提醒（仍有时间就保留、无时间就无操作）。
  def sync_follow_up_schedule
    Crm::ScheduleEvent.sync_opportunity_follow_up(
      Current.account, @opportunity, @opportunity.next_follow_up_at, true, current_user.id
    )
  end

  def opportunity_params
    params.require(:opportunity).permit(
      :name, :crm_customer_id, :owner_id, :amount_micros, :currency,
      :sales_stage, :probability, :expected_close_date, :current_need,
      :competitor, :loss_reason, :next_action, :last_activity_at, :opportunity_remark,
      :important, :next_follow_up_at
    )
  end

  def permitted_params
    params.permit(:page, :filter, :sales_stage, :customer_id, :sort, :direction)
  end
end
