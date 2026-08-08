class Api::V1::Accounts::Crm::CustomersController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_customer, only: [:show, :update, :destroy, :claim, :release, :attach, :detach, :audits, :detail]

  RESULTS_PER_PAGE = 15
  MAX_IMPORT_ROWS = 2000

  # 列筛选：查询参数 → 数据库列，逐个按 present? 叠加。
  COLUMN_FILTERS = {
    status: :customer_status,
    customer_level: :customer_level,
    customer_group: :customer_group,
    product_group: :product_group,
    source_channel: :source_channel,
    account_owner_id: :account_owner_id
  }.freeze

  # 可排序列白名单（防注入）：查询参数 sort → 数据库列。均为数字列，走 sort_clause 的 COALESCE(col,0)。
  SORT_COLUMNS = {
    'deal_amount' => :deal_total_amount_micros,
    'deal_count' => :deal_order_count,
    'completeness' => :info_completeness_score
  }.freeze

  def index
    @customers_scope = filtered_customers
    @customers_count = @customers_scope.count
    @customers = @customers_scope
                 .order(sort_clause)
                 .page(permitted_params[:page] || 1)
                 .per(results_per_page)
  end

  # 指定 sort 列时按 asc/desc 排序，否则默认按更新时间倒序；
  # 流失预警视图默认按最久未互动优先（分诊语义）。
  # 用 COALESCE 把 NULL 当 0（与表格显示的 ¥0 一致），避免 NULL 被排到最前/最后。
  def sort_clause
    column = SORT_COLUMNS[params[:sort]]
    return Arel.sql("#{LAST_TOUCH_SQL} ASC") if column.nil? && params[:filter] == 'churn_risk'
    return { updated_at: :desc } unless column

    direction = params[:direction] == 'asc' ? 'ASC' : 'DESC'
    Arel.sql("COALESCE(#{column}, 0) #{direction}, id DESC")
  end

  def show; end

  def create
    @customer = Current.account.crm_customers.create!(customer_params)
    @customer.sync_contacts(contact_entries)
  end

  # 电话归一化：只留数字，再剥中国手机号的 86/0086 前缀（86+1 开头 11 位），
  # 使 +86 138-0013-8000 与 13800138000 判为同号。
  PHONE_NORM_SQL = "NULLIF(REGEXP_REPLACE(REGEXP_REPLACE(COALESCE(%s, ''), '\\D', '', 'g'), '^(00)?86(1\\d{10})$', '\\2'), '')".freeze

  # 存量查重维度：字段 → 归一化 SQL 表达式 + 最短有效长度（过滤空值/无意义短值）。
  DUP_DIMENSIONS = {
    'contact_email' => { expr: "LOWER(NULLIF(TRIM(contact_email), ''))", min_len: 5 },
    'contact_phone' => { expr: format(PHONE_NORM_SQL, 'contact_phone'), min_len: 6 },
    'whats_app' => { expr: format(PHONE_NORM_SQL, 'whats_app'), min_len: 6 },
    'name' => { expr: 'LOWER(TRIM(name))', min_len: 2 }
  }.freeze
  DUP_GROUPS_PER_DIMENSION = 50

  # 存量客户查重板块：全库按维度归组列出重复客户（跨负责人撞单检测才有意义，
  # 故不按辖区收口；行内只暴露 dedupe_row 的有限字段）。
  def duplicates
    payload = DUP_DIMENSIONS.transform_values { |dim| dimension_groups(dim[:expr], dim[:min_len]) }
    render json: { payload: payload }
  end

  # 流失预警口径：私海成交客户，最后互动超过 CHURN_RISK_DAYS 天。
  # 最后互动 = 跟进记录 / 往来邮件 / 订单日期 三者最新，建档时间兜底（新建档不误报）。
  CHURN_RISK_DAYS = 30
  LAST_TOUCH_SQL = <<~SQL.squish
    GREATEST(
      crm_customers.created_at,
      COALESCE(crm_customers.last_follow_up_at, crm_customers.created_at),
      COALESCE((SELECT MAX(e.email_date) FROM crm_emails e WHERE e.crm_customer_id = crm_customers.id), crm_customers.created_at),
      COALESCE((SELECT MAX(o.order_date::timestamp) FROM crm_sales_orders o WHERE o.crm_customer_id = crm_customers.id), crm_customers.created_at)
    )
  SQL

  # 流失预警角标：当前用户可见范围（业务员本人/主管团队/管理员全部）内的预警客户数。
  def churn_risk_count
    render json: { count: restrict_by_org(churn_risk_scope(Current.account.crm_customers)).count }
  end

  # 邮箱身份识别（邮件阅读区悬浮卡）：同事 / 我的客户 / 公海客户 / 同事客户(撞单) / 陌生人。
  def identify
    email = params[:email].to_s.strip.downcase
    return render json: { type: 'stranger' } if email.blank?

    colleague = Current.account.users.where('LOWER(users.email) = ?', email).first
    return render json: { type: 'colleague', name: colleague.name } if colleague

    customer = Current.account.crm_customers.where('LOWER(contact_email) = ?', email).first
    return render json: { type: 'stranger' } if customer.nil?

    type = if customer.is_in_public_pool
             'public'
           elsif customer.account_owner_id == current_user.id
             'mine'
           else
             'other'
           end
    render json: { type: type, customer: dedupe_row(customer) }
  end

  DEDUPE_SEARCH_LIMIT = 50

  # 主动查重检索：按范围+关键词全库搜（跨负责人撞单检索），返回表格行。
  def dedupe_search
    q = params[:q].to_s.strip
    return render json: { payload: [] } if q.length < 2

    rows = dedupe_search_scope(q, params[:scope].to_s).order(:id).limit(DEDUPE_SEARCH_LIMIT)
    render json: { payload: rows.map { |c| dedupe_search_row(c) } }
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

  # 认领：公海客户归当前用户私海。分组私海上限由模型 pool_limit 校验拦截；
  # 原归属人受领回冷却期限制（豁免名单成员除外）。
  def claim
    if (message = claim_cooldown_message)
      return render json: { message: message }, status: :forbidden
    end

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

  # 客户详情大页：一次聚合客户 + 商机 / 跟进时间线 / 待办 / 订单 / 报价（文件已在客户里）。
  def detail
    @opportunities = @customer.opportunities.order(updated_at: :desc).limit(20)
    @orders = @customer.sales_orders.order(order_date: :desc).limit(20)
    @quotes = @customer.quotes.order(Arel.sql('COALESCE(quote_date, created_at) DESC')).limit(20)
    @notes = Current.account.crm_follow_up_notes
                    .where(crm_customer_id: @customer.id).order(created_at: :desc).limit(30)
    @tasks = Current.account.crm_follow_up_tasks
                    .where(crm_customer_id: @customer.id)
                    .order(Arel.sql('due_at IS NULL, due_at ASC')).limit(30)
  end

  # 操作历史：该客户的审计记录（谁在何时改了哪些字段）。
  def audits
    rows = @customer.audits.order(created_at: :desc).limit(80).map do |audit|
      {
        id: audit.id,
        action: audit.action,
        changed_fields: audit.audited_changes.keys,
        user_name: audit.user&.crm_display_name || audit.username || '系统',
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

  # 领回冷却：原归属人在冷却天数内不能把自己转入公海的客户领回；返回拦截文案，nil = 放行。
  def claim_cooldown_message
    settings = Crm::PublicPoolSetting.for_account(Current.account)
    days = settings.claim_cooldown_days.to_i
    return nil if days <= 0 || settings.exempt_user_ids.include?(current_user.id)
    return nil unless @customer.previous_owner_id == current_user.id && @customer.public_pool_at.present?

    remaining = ((@customer.public_pool_at + days.days - Time.current) / 1.day).ceil
    remaining.positive? ? "该客户由你转入公海，冷却期内不能领回（还需 #{remaining} 天）" : nil
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

  # 池筛选：公海 / 私海 / 我的 / 未分配 / 流失预警。
  def pool_scope(scope)
    case params[:filter]
    when 'public_pool' then scope.in_public_pool
    when 'private' then scope.where(is_in_public_pool: false)
    when 'mine' then scope.owned_by(current_user.id)
    when 'unassigned' then scope.where(account_owner_id: nil, is_in_public_pool: false)
    when 'churn_risk' then churn_risk_scope(scope)
    else scope
    end
  end

  def churn_risk_scope(scope)
    scope.where(is_in_public_pool: false).where.not(first_deal_at: nil)
         .where("#{LAST_TOUCH_SQL} < ?", CHURN_RISK_DAYS.days.ago)
  end

  # 建档联系人：主联系人（快照字段）+ 建档页录入的其他联系人，逐个建/复用 Contact 挂到客户。
  def contact_entries
    primary = {
      name: @customer.primary_contact_name, email: @customer.contact_email,
      phone: @customer.contact_phone, job_title: @customer.contact_job_title, is_primary: true
    }
    [primary, *extra_contact_params]
  end

  def extra_contact_params
    Array(params.dig(:customer, :contacts)).filter_map do |raw|
      permitted = raw.permit(:name, :email, :phone, :job_title).to_h.symbolize_keys
      permitted if permitted[:email].present?
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

  # 单维度重复组：归一化值出现 >1 次的分组（按重复条数倒序，取前 DUP_GROUPS_PER_DIMENSION 组）。
  def dimension_groups(expr, min_len)
    scope = Current.account.crm_customers
    counts = scope.group(Arel.sql(expr))
                  .having(Arel.sql("#{expr} IS NOT NULL AND LENGTH(#{expr}) >= #{min_len.to_i} AND COUNT(*) > 1"))
                  .count
    values = counts.sort_by { |_v, count| -count }.first(DUP_GROUPS_PER_DIMENSION).map(&:first)
    return [] if values.empty?

    # 命名绑定：expr 的正则里含 ?（如 (00)?），位置绑定会把它误当占位符
    rows = scope.where("#{expr} IN (:values)", values: values).order(:id).group_by { |c| normalized_value(expr, c) }
    values.map { |v| { value: v, customers: rows.fetch(v, []).map { |c| dedupe_row(c) } } }
  end

  # 在 Ruby 侧复算归一化值，把整组客户按 SQL 分组键对上号。
  def normalized_value(expr, customer)
    case expr
    when DUP_DIMENSIONS['contact_email'][:expr] then customer.contact_email.to_s.strip.downcase.presence
    when DUP_DIMENSIONS['contact_phone'][:expr] then normalized_phone(customer.contact_phone)
    when DUP_DIMENSIONS['whats_app'][:expr] then normalized_phone(customer.whats_app)
    else customer.name.to_s.strip.downcase
    end
  end

  # 与 PHONE_NORM_SQL 同规则的 Ruby 版。
  def normalized_phone(raw)
    raw.to_s.gsub(/\D/, '').sub(/\A(00)?86(1\d{10})\z/, '\2').presence
  end

  # 单列 ILIKE 的检索范围：范围键 → 列名。
  DEDUPE_SCOPE_COLUMNS = {
    'name' => 'name', 'code' => 'customer_code', 'email' => 'contact_email', 'contact' => 'primary_contact_name'
  }.freeze

  # 主动查重的范围检索。电话按去符号后的数字包含匹配；邮箱后缀匹配 @ 结尾段。
  def dedupe_search_scope(query, scope_key)
    base = Current.account.crm_customers
    like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    column = DEDUPE_SCOPE_COLUMNS[scope_key]
    return base.where("#{column} ILIKE :q", q: like) if column

    case scope_key
    when 'email_suffix'
      base.where('contact_email ILIKE :q', q: "%@#{ActiveRecord::Base.sanitize_sql_like(query.delete_prefix('@'))}")
    when 'phone' then dedupe_phone_scope(base, query)
    when 'social' then base.where('whats_app ILIKE :q OR wechat ILIKE :q OR linkedin ILIKE :q', q: like)
    else dedupe_all_scope(base, like, query)
    end
  end

  # 库侧列按 PHONE_NORM_SQL 归一（剥 86 前缀），查询词也生成「原样 + 剥 86」两个变体，
  # 保证 +86 版与裸号版互相都能搜到。
  def dedupe_phone_scope(base, query)
    digits = query.gsub(/\D/, '')
    variants = [digits, digits.sub(/\A(00)?86/, '')].uniq.select { |d| d.length >= 4 }
    return base.none if variants.empty?

    phone_expr = format(PHONE_NORM_SQL, 'contact_phone')
    wa_expr = format(PHONE_NORM_SQL, 'whats_app')
    clauses = variants.each_index.map { |i| "#{phone_expr} LIKE :d#{i} OR #{wa_expr} LIKE :d#{i}" }.join(' OR ')
    binds = variants.each_with_index.to_h { |d, i| [:"d#{i}", "%#{d}%"] }
    base.where(clauses, **binds)
  end

  # 「全部」：文本字段 OR 检索；关键词含 ≥4 位数字时并入电话匹配。
  def dedupe_all_scope(base, like, query)
    text_hit = base.where(
      'name ILIKE :q OR customer_code ILIKE :q OR contact_email ILIKE :q OR ' \
      'primary_contact_name ILIKE :q OR whats_app ILIKE :q OR wechat ILIKE :q OR linkedin ILIKE :q', q: like
    )
    digits = query.gsub(/\D/, '')
    return text_hit if digits.length < 4

    text_hit.or(dedupe_phone_scope(base, query))
  end

  # 主动查重结果行：对齐查重表格列（编号/阶段/公司/联系人/邮箱/电话）+ 归属。
  def dedupe_search_row(customer)
    dedupe_row(customer).merge(
      contact_name: customer.primary_contact_name,
      email: customer.contact_email,
      phone: customer.contact_phone
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

    {
      id: customer.id, name: customer.name, customer_code: customer.customer_code, owner: owner_label(customer),
      status: customer.customer_status, in_public_pool: customer.is_in_public_pool
    }
  end

  def owner_label(customer)
    return '🌊 公海' if customer.is_in_public_pool
    return "👤 #{customer.account_owner.crm_display_name}" if customer.account_owner_id

    '未分配'
  end

  # 默认每页 15；选择器等场景可传 per_page 一次拿全（上限 200）。
  def results_per_page
    requested = permitted_params[:per_page].to_i
    requested.positive? ? [requested, 200].min : RESULTS_PER_PAGE
  end

  def permitted_params
    params.permit(:page, :per_page, :filter, :status, :customer_level, :customer_group, :product_group, :source_channel, :account_owner_id)
  end
end
