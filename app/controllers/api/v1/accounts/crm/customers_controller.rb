class Api::V1::Accounts::Crm::CustomersController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_customer, only: [:show, :update, :destroy, :claim, :release, :share, :attach, :detach, :audits, :detail, :favorite, :unfavorite, :attach_contact, :schedule_follow_up, :merge]

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

  # 可排序列白名单（防注入）：sort 参数 → SQL 排序表达式。文本列按 LOWER 排、数字列 COALESCE 兜 NULL。
  # 「最近联系时间」(last_touch) 用 LAST_TOUCH_SQL，在 sort_clause 里单独处理（该常量定义在本行之后）。
  SORT_EXPRESSIONS = {
    'name' => 'LOWER(crm_customers.name)',
    'country' => 'LOWER(crm_customers.trade_country)',
    'contact' => 'LOWER(crm_customers.primary_contact_name)',
    'email' => 'LOWER(crm_customers.contact_email)',
    'completeness' => 'COALESCE(crm_customers.info_completeness_score, 0)',
    'deal_amount' => 'COALESCE(crm_customers.deal_total_amount_micros, 0)',
    'star' => 'COALESCE(crm_customers.deal_total_amount_micros, 0)',
    'deal_count' => 'COALESCE(crm_customers.deal_order_count, 0)',
    'status' => 'LOWER(crm_customers.customer_status)',
    'source' => 'LOWER(crm_customers.source_channel)',
    'region' => 'LOWER(crm_customers.trade_region)'
  }.freeze

  def index
    @customers_scope = filtered_customers
    @customers_count = @customers_scope.count
    @customers = @customers_scope
                 .select("crm_customers.*, (#{LAST_TOUCH_SQL}) AS last_touch_at")
                 .order(sort_clause)
                 .page(permitted_params[:page] || 1)
                 .per(results_per_page)
    @favorited_ids = favorited_ids_for(@customers.map(&:id))
  end

  # 特别关注（每人各标）：收藏 / 取消收藏。
  def favorite
    Crm::CustomerFavorite.find_or_create_by!(
      account_id: Current.account.id, user_id: current_user.id, crm_customer_id: @customer.id
    )
    head :ok
  end

  def unfavorite
    Crm::CustomerFavorite.where(
      account_id: Current.account.id, user_id: current_user.id, crm_customer_id: @customer.id
    ).delete_all
    head :ok
  end

  # 指定 sort 列时按 asc/desc 排序，否则默认按更新时间倒序；
  # 流失预警视图默认按最久未互动优先（分诊语义）。
  # 用 COALESCE 把 NULL 当 0（与表格显示的 ¥0 一致），避免 NULL 被排到最前/最后。
  def sort_clause
    direction = params[:direction] == 'asc' ? 'ASC' : 'DESC'
    # 「最近联系时间」排序：跟进/往来邮件/订单三者最新（LAST_TOUCH_SQL），默认倒序（最近在前）。
    return Arel.sql("#{LAST_TOUCH_SQL} #{direction}, crm_customers.id DESC") if params[:sort] == 'last_touch'

    expr = SORT_EXPRESSIONS[params[:sort]]
    return Arel.sql("#{LAST_TOUCH_SQL} ASC") if expr.nil? && params[:filter] == 'churn_risk'
    return { updated_at: :desc } unless expr

    Arel.sql("#{expr} #{direction} NULLS LAST, crm_customers.id DESC")
  end

  def show; end

  # 只设置「下次跟进时间」。用 update_columns 跳过全量校验——历史/小满迁入客户
  # 常有既有脏数据（如 trade_country 非法），不该阻塞这一窄字段的写入。
  # add_to_schedule 为真时同步 upsert 一条关联本客户的日程提醒（幂等，可从日程跳回客户）。
  def schedule_follow_up
    at = params[:next_follow_up_at]
    @customer.update_columns(next_follow_up_at: at, updated_at: Time.current)
    Crm::ScheduleEvent.sync_follow_up(Current.account, @customer, at, params[:add_to_schedule], current_user.id)
    head :ok
  end

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

  # 列表顶部概览卡：沿用当前视图/筛选口径（我的/团队/搜索均同步）。
  def stats
    scope = filtered_customers
    render json: {
      customers: scope.count,
      new_this_month: scope.where('crm_customers.created_at >= ?', Time.current.beginning_of_month).count,
      open_opportunities: Current.account.crm_opportunities.open_stages.where(crm_customer_id: scope.select(:id)).count,
      with_orders: scope.where('deal_order_count > 0').count
    }
  end

  # 邮箱身份识别（邮件阅读区悬浮卡）：同事 / 我的客户 / 公海客户 / 同事客户(撞单) / 陌生人。
  def identify
    email = params[:email].to_s.strip.downcase
    return render json: { type: 'stranger' } if email.blank?

    colleague = Current.account.users.where('LOWER(users.email) = ?', email).first
    return render json: { type: 'colleague', name: colleague.name } if colleague

    customer = Current.account.crm_customers.where('LOWER(contact_email) = ?', email).first
    # 次要联系人：主邮箱没命中时，按已挂到客户的 Contact 找归属（与收信归档口径一致）。
    customer ||= customer_by_contact(email)
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

  # 添加到已有的顾客：把某邮箱作为联系人挂到本客户（小满只同步了公司一个联系人时，
  # 用来收编同公司其他来信人），并把该地址已收的未归档邮件补挂到本客户。
  def attach_contact
    email = params[:email].to_s.strip.downcase
    return render json: { error: '邮箱无效' }, status: :unprocessable_entity unless email.include?('@')

    @customer.sync_contacts([{ email: email, name: params[:name].to_s.strip }])
    Current.account.crm_emails.where(crm_customer_id: nil)
           .where('LOWER(from_address) = ?', email)
           .update_all(crm_customer_id: @customer.id)
    render json: { ok: true, customer: dedupe_row(@customer) }
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
    # 编辑弹窗带来的「其他联系人」：upsert（不删除既有邮件自动挂接的联系人）。
    @customer.sync_contacts(contact_entries) if params.dig(:customer, :contacts).present?
  end

  # 批量分配：任何 CRM 角色都可把「自己名下」的私海客户分配给任意成员；
  # 部门主管分配团队成员的客户时目标限本团队；管理员不受限。
  # 客户名下的商机（私海）、订单、报价、往来邮件一并归入新业务员名下。
  def reassign
    target_id = params[:owner_id].to_i
    return render json: { error: '目标成员不存在' }, status: :unprocessable_entity unless Current.account.account_users.exists?(user_id: target_id)

    scope = scope_by_team_owner(Current.account.crm_customers.where(is_in_public_pool: false), column: :account_owner_id)
    customers = scope.where(id: Array(params[:ids]))
    return render json: { error: '只能分配给自己团队的业务员' }, status: :forbidden unless reassign_target_allowed?(customers, target_id)

    customer_ids = customers.pluck(:id)
    Current.account.crm_customers.where(id: customer_ids).update_all(account_owner_id: target_id, updated_at: Time.current)
    cascade_reassign(customer_ids, target_id, cascade_options)
    render json: { reassigned: customer_ids.size }
  end

  # 批量改字段：勾选客户后批量改「客户状态」/「客户分组」。权限同分配——
  # 只动自己辖区内(业务员本人/主管本团队/管理员全部)的私海客户；未传/无效字段忽略。
  def bulk_update
    attrs = bulk_update_attrs
    return render json: { error: '没有要修改的字段' }, status: :unprocessable_entity if attrs.blank?

    scope = scope_by_team_owner(Current.account.crm_customers.where(is_in_public_pool: false), column: :account_owner_id)
    ids = scope.where(id: Array(params[:ids])).pluck(:id)
    return render json: { updated: 0 } if ids.empty?

    Current.account.crm_customers.where(id: ids).update_all(attrs.merge(updated_at: Time.current))
    render json: { updated: ids.size }
  end

  # 客户合并：把 source 客户的邮件/订单/PI/报价/商机/跟进/联系人/生产单迁移到本客户（存活方），
  # 空字段用 source 补齐后删除 source。权限：管理员/副管，或两个客户都归当前用户。
  def merge
    source = Current.account.crm_customers.find_by(id: params[:source_id])
    if source.nil? || source.id == @customer.id
      return render json: { error: '要合并的客户无效' }, status: :unprocessable_entity
    end
    return render json: { error: '无权合并该客户' }, status: :forbidden unless merge_allowed?(source)

    ActiveRecord::Base.transaction do
      migrate_customer_associations(source.id, @customer.id)
      fill_blank_fields(@customer, source)
      @customer.save!(validate: false)
      source.destroy!
    end
    @customer.recompute_deal_rollup!
    render 'api/v1/accounts/crm/customers/show'
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

  # 共享客户：设置协作人（被共享成员可见该客户）。仅负责人本人或管理员/副管理员可共享。
  def share
    return render json: { error: '无权共享该客户' }, status: :forbidden unless share_allowed?

    ids = Array(params[:user_ids]).map(&:to_i).select(&:positive?).uniq
    @customer.update!(shared_user_ids: ids)
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
    # 最近联系：跟进/往来邮件/订单三者取最新（与客户列表同口径），详情页据此展示，避免只按手动跟进算成「—」。
    @last_touch_at = Current.account.crm_customers.where(id: @customer.id).pick(Arel.sql(LAST_TOUCH_SQL))
    @opportunities = @customer.opportunities.order(updated_at: :desc).limit(20)
    @orders = @customer.sales_orders.order(order_date: :desc).limit(20).with_attached_files
    @pis = @customer.crm_pis.order(pi_date: :desc).limit(20)
    @quotes = @customer.quotes.order(Arel.sql('COALESCE(quote_date, created_at) DESC')).limit(20)
    # 该客户的 MES 生产订单（不看创建人：助理在共享客户上建的生产单，老板也在此看到）。
    @production_orders = Current.account.mes_production_orders
                                .where(crm_customer_id: @customer.id).order(created_at: :desc).limit(20)
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

  # 合并权限：管理员/副管，或存活方与被并方都归当前用户。
  def merge_allowed?(source)
    au = Current.account_user
    return true if au.administrator? || au.crm_deputy_admin?

    @customer.account_owner_id == current_user.id && source.account_owner_id == current_user.id
  end

  # 空字段合并：存活方为空、被并方有值时用被并方补齐。
  MERGE_FILL_FIELDS = %w[website industry address trade_country trade_region trade_city
                         currency_preference customer_group customer_level product_group
                         source_channel customer_status risk_level primary_contact_name
                         contact_job_title contact_email contact_phone whats_app wechat
                         linkedin customer_remark].freeze

  def fill_blank_fields(target, source)
    MERGE_FILL_FIELDS.each do |f|
      target[f] = source[f] if target[f].blank? && source[f].present?
    end
  end

  # 关联迁移：按 account_id + crm_customer_id 直改归属；收藏去重（删被并方的收藏）。
  def migrate_customer_associations(from_id, to_id)
    aid = Current.account.id
    stamp = { crm_customer_id: to_id, updated_at: Time.current }
    [Crm::Email, Crm::SalesOrder, Crm::Pi, Crm::Quote, Crm::Opportunity,
     Crm::FollowUpNote, Crm::FollowUpTask, Mes::ProductionOrder].each do |klass|
      klass.where(account_id: aid, crm_customer_id: from_id).update_all(stamp)
    end
    Contact.where(account_id: aid, crm_customer_id: from_id).update_all(crm_customer_id: to_id, updated_at: Time.current)
    Crm::CustomerFavorite.where(account_id: aid, crm_customer_id: from_id).delete_all
  end

  # 批量修改字段：状态限枚举、分组走「客户设置」动态配置（与单条编辑同口径，不硬校验）。
  # 仅收传入的字段，避免误清空未提及的列。
  def bulk_update_attrs
    attrs = {}
    status = params[:customer_status].to_s.strip
    attrs[:customer_status] = status if Crm::Customer::CUSTOMER_STATUSES.include?(status)
    group = params[:customer_group].to_s.strip
    attrs[:customer_group] = group if group.present?
    attrs
  end

  # 分配级联：公海中的商机不动（保持共享池语义），其余关联数据全部随客户换负责人。
  # 转移勾选项：商机/订单(含报价)/邮件 是否随客户转给新负责人。未传 cascade 时默认全带（向后兼容）。
  def cascade_options
    c = params[:cascade]
    return { opportunities: true, orders: true, emails: true } if c.blank?

    bool = ->(v) { ActiveModel::Type::Boolean.new.cast(v) }
    { opportunities: bool.call(c[:opportunities]), orders: bool.call(c[:orders]), emails: bool.call(c[:emails]) }
  end

  def cascade_reassign(customer_ids, target_id, opts)
    return if customer_ids.empty?

    stamp = { owner_id: target_id, updated_at: Time.current }
    if opts[:opportunities]
      Current.account.crm_opportunities.where(crm_customer_id: customer_ids, is_in_public_pool: false).update_all(stamp)
    end
    if opts[:orders]
      Current.account.crm_sales_orders.where(crm_customer_id: customer_ids).update_all(stamp)
      Current.account.crm_quotes.where(crm_customer_id: customer_ids).update_all(stamp)
    end
    Current.account.crm_emails.where(crm_customer_id: customer_ids).update_all(stamp) if opts[:emails]
  end

  # 目标校验：全是自己的客户→任意成员；含团队成员的客户→目标须在自己辖区内；管理员不限。
  def reassign_target_allowed?(customers, target_id)
    visible = crm_team_visible_owner_ids
    return true if visible == :all || visible.include?(target_id)

    customers.where.not(account_owner_id: current_user.id).none?
  end

  # 按 id 直取收口到可读范围（可见私海 ∪ 公海，见 base_controller#visible_customers）。
  # 否则任意业务员可越权读改他人私海客户及其商机/订单/PI/报价（IDOR）。管理员/副管不受限。
  def fetch_customer
    @customer = visible_customers.find(params[:id])
  end

  # 按已挂客户的 Contact（次要联系人）邮箱找归属客户；无则 nil。
  def customer_by_contact(email)
    contact = Current.account.contacts
                     .where('LOWER(email) = ?', email).where.not(crm_customer_id: nil).first
    contact && Current.account.crm_customers.find_by(id: contact.crm_customer_id)
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
  # 私海侧按 CRM 团队收口（管理员看全部/CRM 团队负责人看本团队/业务员看自己）；公海是共享池不限。
  def filtered_customers
    scope = pool_scope(Current.account.crm_customers)
    # 公海=全公司共享；shared 按 shared_user_ids 收口；shared_out 已按 owner 收口——均不叠加团队辖区限制。
    scope = restrict_by_org(scope) unless params[:filter].in?(%w[public_pool shared shared_out])
    scope = scope.favorited_by(current_user.id) if params[:favorited_only].present?
    apply_customer_filters(scope)
  end

  # 当前用户在给定客户里收藏了哪些（列表 favorited 标记用）。
  def favorited_ids_for(ids)
    return Set.new if ids.blank?

    Set.new(
      Crm::CustomerFavorite
        .where(account_id: Current.account.id, user_id: current_user.id, crm_customer_id: ids)
        .pluck(:crm_customer_id)
    )
  end

  def apply_customer_filters(scope)
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    # 客户星级筛选（star=0..5，按累计成交额区间）。
    scope = scope.by_star(params[:star]) if params[:star].present?
    scope = apply_keyword_filter(scope)
    scope = scope.where(account_owner_id: team_member_ids(params[:team_id])) if params[:team_id].present?
    scope
  end

  # 关键词同时匹配公司名 + 联系人 + 联系邮箱/电话，便于按联系人找客户。
  def apply_keyword_filter(scope)
    return scope if params[:q].blank?

    scope.where(
      'name ILIKE :q OR primary_contact_name ILIKE :q OR contact_email ILIKE :q OR contact_phone ILIKE :q',
      q: "%#{params[:q]}%"
    )
  end

  # 按 CRM 角色限定可见负责人（非公海视图）：管理员全部 / 主管团队 / 业务员本人；
  # 额外：被共享（协作人含我）的客户也可见。
  def restrict_by_org(scope)
    ids = crm_team_visible_owner_ids
    return scope if ids == :all

    scope.where(
      'crm_customers.account_owner_id IN (:ids) OR :uid = ANY(crm_customers.shared_user_ids)',
      ids: ids, uid: current_user.id
    )
  end

  # 共享权限：管理员/副管理员，或该客户当前负责人本人。
  def share_allowed?
    au = Current.account_user
    au.administrator? || au.crm_deputy_admin? || @customer.account_owner_id == current_user.id
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
    # 建单可选客户：本人名下 + 共享给本人的（助理在共享客户上建 PI/报价/订单）。
    when 'mine_shared' then scope.where('crm_customers.account_owner_id = :uid OR :uid = ANY(crm_customers.shared_user_ids)', uid: current_user.id)
    # 「共享给我的」列表视图：只看别人共享给本人的客户（不含自己名下的）。
    when 'shared' then scope.where(':uid = ANY(crm_customers.shared_user_ids)', uid: current_user.id)
    # 「我共享出去的」（管理层）：本人名下、且已共享给协作人的客户。
    when 'shared_out' then scope.where("crm_customers.account_owner_id = :uid AND crm_customers.shared_user_ids <> '{}'", uid: current_user.id)
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
    params.permit(:page, :per_page, :filter, :status, :star, :customer_group, :product_group, :source_channel, :account_owner_id)
  end
end
