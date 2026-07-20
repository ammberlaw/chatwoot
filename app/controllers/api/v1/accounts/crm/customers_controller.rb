class Api::V1::Accounts::Crm::CustomersController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_customer, only: [:show, :update, :destroy, :claim, :release, :attach, :detach, :audits]

  RESULTS_PER_PAGE = 15
  MAX_IMPORT_ROWS = 2000

  # 列筛选：查询参数 → 数据库列，逐个按 present? 叠加。
  COLUMN_FILTERS = {
    status: :customer_status,
    customer_group: :customer_group,
    product_group: :product_group,
    source_channel: :source_channel,
    account_owner_id: :account_owner_id
  }.freeze

  # 可排序列白名单（防注入）：查询参数 sort → 数据库列。
  SORT_COLUMNS = { 'deal_amount' => :deal_total_amount_micros }.freeze

  def index
    @customers_scope = filtered_customers
    @customers_count = @customers_scope.count
    @customers = @customers_scope
                 .order(sort_clause)
                 .page(permitted_params[:page] || 1)
                 .per(results_per_page)
  end

  # 指定 sort 列时按 asc/desc 排序，否则默认按更新时间倒序。
  # 用 COALESCE 把 NULL 当 0（与表格显示的 ¥0 一致），避免 NULL 被排到最前/最后。
  def sort_clause
    column = SORT_COLUMNS[params[:sort]]
    return { updated_at: :desc } unless column

    direction = params[:direction] == 'asc' ? 'ASC' : 'DESC'
    Arel.sql("COALESCE(#{column}, 0) #{direction}, id DESC")
  end

  def show; end

  def create
    @customer = Current.account.crm_customers.create!(customer_params)
  end

  # 客户建档实时查重：邮箱精确命中(阻止) + 公司名相似(提醒)。
  def check_duplicate
    email = params[:email].to_s.strip
    name = params[:name].to_s.strip
    render json: {
      email_hit: email.present? ? dedupe_row(Current.account.crm_customers.where('LOWER(contact_email) = ?', email.downcase).first) : nil,
      name_hits: name.length >= 2 ? name_matches(name) : []
    }
  end

  # 批量导入：吃前端映射好的行（键=CRM字段）。管理层校验见 CustomerPolicy#import?。
  def import
    rows = Array(params[:rows])
    return render json: { error: '没有可导入的数据' }, status: :unprocessable_entity if rows.blank?
    return render json: { error: "单次最多导入 #{MAX_IMPORT_ROWS} 条" }, status: :unprocessable_entity if rows.size > MAX_IMPORT_ROWS

    render json: Crm::CustomerImportService.new(
      account: Current.account, user: current_user,
      rows: rows.map { |r| r.permit!.to_h }, default_owner_id: params[:default_owner_id]
    ).call
  end

  def update
    @customer.update!(customer_params)
  end

  # 批量分配：任何 CRM 角色都可把「自己名下」的私海客户分配给任意成员；
  # 部门主管分配团队成员的客户时目标限本团队；管理员不受限。
  # 客户名下的商机（私海）、订单、报价、往来邮件一并归入新业务员名下。
  def reassign
    target_id = params[:owner_id].to_i
    return render json: { error: '目标成员不存在' }, status: :unprocessable_entity unless Current.account.account_users.exists?(user_id: target_id)

    scope = scope_by_owner(Current.account.crm_customers.where(is_in_public_pool: false), column: :account_owner_id)
    customers = scope.where(id: Array(params[:ids]))
    return render json: { error: '只能分配给自己团队的业务员' }, status: :forbidden unless reassign_target_allowed?(customers, target_id)

    customer_ids = customers.pluck(:id)
    Current.account.crm_customers.where(id: customer_ids).update_all(account_owner_id: target_id, updated_at: Time.current)
    cascade_reassign(customer_ids, target_id)
    render json: { reassigned: customer_ids.size }
  end

  # 认领：公海客户归当前用户私海。分组私海上限由模型 pool_limit 校验拦截。
  def claim
    @customer.update!(account_owner_id: current_user.id, is_in_public_pool: false, public_pool_at: nil)
    render 'api/v1/accounts/crm/customers/show'
  end

  # 转公海：清空负责人、进公海。
  def release
    @customer.move_to_public_pool!
    render 'api/v1/accounts/crm/customers/show'
  end

  # 附件上传（追加，不覆盖已有）
  def attach
    @customer.files.attach(params[:files])
    render 'api/v1/accounts/crm/customers/show'
  end

  # 删除单个附件
  def detach
    @customer.files.find(params[:attachment_id]).purge
    render 'api/v1/accounts/crm/customers/show'
  end

  def destroy
    @customer.destroy!
    head :ok
  end

  # 操作历史：该客户的审计记录（谁在何时改了哪些字段）。
  def audits
    rows = @customer.audits.order(created_at: :desc).limit(80).map do |audit|
      {
        id: audit.id,
        action: audit.action,
        changed_fields: audit.audited_changes.keys,
        user_name: audit.user&.name || audit.username || '系统',
        created_at: audit.created_at
      }
    end
    render json: { payload: rows }
  end

  private

  # 分配级联：公海中的商机不动（保持共享池语义），其余关联数据全部随客户换负责人。
  def cascade_reassign(customer_ids, target_id)
    return if customer_ids.empty?

    stamp = { owner_id: target_id, updated_at: Time.current }
    Current.account.crm_opportunities.where(crm_customer_id: customer_ids, is_in_public_pool: false).update_all(stamp)
    Current.account.crm_sales_orders.where(crm_customer_id: customer_ids).update_all(stamp)
    Current.account.crm_quotes.where(crm_customer_id: customer_ids).update_all(stamp)
    Current.account.crm_emails.where(crm_customer_id: customer_ids).update_all(stamp)
  end

  # 目标校验：全是自己的客户→任意成员；含团队成员的客户→目标须在自己辖区内；管理员不限。
  def reassign_target_allowed?(customers, target_id)
    visible = crm_visible_owner_ids
    return true if visible == :all || visible.include?(target_id)

    customers.where.not(account_owner_id: current_user.id).none?
  end

  def fetch_customer
    @customer = Current.account.crm_customers.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Customer)
  end

  # 支持常用视图筛选：公海池/我的/未分配 + 按状态/客户分组/产品分组/负责人。
  # 私海侧按部门授权收口（管理员看全部/主管看本部门/业务员看自己）；公海是共享池不限。
  def filtered_customers
    scope = pool_scope(Current.account.crm_customers)
    scope = restrict_by_org(scope) unless params[:filter] == 'public_pool'
    apply_customer_filters(scope)
  end

  def apply_customer_filters(scope)
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = scope.where('name ILIKE ?', "%#{params[:q]}%") if params[:q].present?
    scope = scope.where(account_owner_id: team_member_ids(params[:team_id])) if params[:team_id].present?
    scope
  end

  # 按 CRM 角色限定可见负责人（非公海视图）：管理员全部 / 主管团队 / 业务员本人。
  def restrict_by_org(scope)
    scope_by_owner(scope, column: :account_owner_id)
  end

  # 团队成员的 user id 集合（admin 按团队筛选客户）。
  def team_member_ids(team_id)
    Current.account.crm_teams.find_by(id: team_id)&.members&.pluck(:id) || []
  end

  # 池筛选：公海 / 私海 / 我的 / 未分配。
  def pool_scope(scope)
    case params[:filter]
    when 'public_pool' then scope.in_public_pool
    when 'private' then scope.where(is_in_public_pool: false)
    when 'mine' then scope.owned_by(current_user.id)
    when 'unassigned' then scope.where(account_owner_id: nil, is_in_public_pool: false)
    else scope
    end
  end

  def customer_params
    params.require(:customer).permit(
      :name, :customer_code, :account_owner_id, :website,
      :trade_country, :trade_region, :trade_city,
      :industry, :customer_level, :source_channel, :currency_preference,
      :customer_status, :customer_group, :product_group, :risk_level,
      :last_follow_up_at, :next_follow_up_at, :is_in_public_pool, :public_pool_at,
      :primary_contact_name, :contact_job_title, :contact_email, :contact_phone,
      :whats_app, :wechat, :contact_preference, :customer_remark,
      :address, :linkedin
    )
  end

  def name_matches(name)
    Current.account.crm_customers
           .where('name ILIKE ?', "%#{name}%")
           .order(updated_at: :desc).limit(5)
           .map { |c| dedupe_row(c) }
  end

  # 查重结果行：含负责人归属标签（公海/负责人/未分配）
  def dedupe_row(customer)
    return nil if customer.nil?

    { id: customer.id, name: customer.name, customer_code: customer.customer_code, owner: owner_label(customer) }
  end

  def owner_label(customer)
    return '🌊 公海' if customer.is_in_public_pool
    return "👤 #{customer.account_owner.name}" if customer.account_owner_id

    '未分配'
  end

  # 默认每页 15；选择器等场景可传 per_page 一次拿全（上限 200）。
  def results_per_page
    requested = permitted_params[:per_page].to_i
    requested.positive? ? [requested, 200].min : RESULTS_PER_PAGE
  end

  def permitted_params
    params.permit(:page, :per_page, :filter, :status, :customer_group, :product_group, :source_channel, :account_owner_id)
  end
end
