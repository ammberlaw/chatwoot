class Api::V1::Accounts::Crm::SalesOrdersController < Api::V1::Accounts::Crm::BaseController
  # 财务（crm_finance）没有 crm_role，会被 CRM 总门禁拦掉，但对账必须看得到销售订单。
  # 与提成表同款：跳过总门禁，本控制器自己把关——财务只读、看全员。
  skip_before_action :ensure_crm_access
  before_action :ensure_crm_or_finance!
  before_action :block_crm_finance_writes!,
                except: [:index, :show, :audits, :convert_preview, :receivable_progress, :production_trace,
                         :erp_export]
  before_action :check_authorization
  before_action :fetch_sales_order,
                only: [:show, :update, :destroy, :attach, :detach, :audits, :convert_preview, :receivable_progress,
                       :production_trace, :erp_export]

  RESULTS_PER_PAGE = 15

  def index
    @sales_orders_scope = filtered_sales_orders
    @sales_orders_count = @sales_orders_scope.count
    # 同一天下单的订单一大把（order_date 存的是 00:00），只按 order_date 排没有稳定次序，
    # 翻页是一页一条 SQL，两次执行的并列次序可能不同——结果就是某条订单在任何一页都不出现。
    # 补 id 兜底，让排序全序唯一（与提成表 order(period_month:, id:) 同一写法）。
    @sales_orders = @sales_orders_scope
                    .order(order_date: :desc, id: :desc)
                    .page(permitted_params[:page] || 1)
                    .per(results_per_page)
    preload_pis
    compute_tab_counts
  end

  def show
    preload_pis([@sales_order])
  end

  def create
    attrs = order_attributes
    # 历史 PI 补录：PI 本来就在客户「文件」页里，不是本地文件。带上它的 attachment_id，
    # 建单时把同一份 blob 复制到订单上——既满足「新建订单必须有附件」，PI 也跟着订单走。
    source_attachment = find_source_attachment(attrs.delete(:source_attachment_id), attrs[:crm_customer_id])
    # 业绩归属人 = 客户归属人（共享客户助理建单，业绩归老板）；显式传 owner_id 优先。
    # handled_by = 实际建单人（留痕）。
    @sales_order = Current.account.crm_sales_orders.new(
      attrs.merge(
        owner_id: attrs[:owner_id].presence || performance_owner_id(attrs[:crm_customer_id]),
        handled_by_id: current_user.id
      )
    )
    # 先挂附件再存：附件必填的校验在 create 时跑，挂在保存之后会被判「没有附件」。
    copy_source_attachment(source_attachment)
    @sales_order.save!
    remember_product_choices(@sales_order.line_items)
  end

  def update
    @sales_order.update!(order_attributes)
  end

  # 读取 PI 自动识别：上传 PDF/Excel，返回字段化结果供前端校对（不落库）。
  def parse_pi
    return render json: { error: '请上传 PI 文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Crm::PiParseService.new(account: Current.account, user: current_user, file: params[:file]).call
    render json: result
  rescue Crm::PiParseService::UnsupportedType, Crm::EmailAiService::NotConfigured => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PI parse] #{e.class}: #{e.message}")
    render json: { error: 'PI 识别失败，请检查文件或稍后重试' }, status: :unprocessable_entity
  end

  # 软删除：进回收箱，不真删。负责人本人可删自己的单；管理员/副管可删任意。
  def destroy
    unless can_delete_order?(@sales_order)
      return render json: { error: '无权删除该订单（仅负责人本人或管理员可删）' }, status: :forbidden
    end

    @sales_order.soft_delete!(current_user)
    head :ok
  end

  # 回收箱列表（仅管理员/副管）：已删订单，供恢复。
  def deleted
    orders = Current.account.crm_sales_orders.only_deleted
                    .includes(:owner, :deleted_by, :crm_customer)
                    .order(deleted_at: :desc)
    render json: {
      payload: orders.map { |o| deleted_order_json(o) },
      count: orders.size
    }
  end

  # 录单用的收款账户下拉（哪个银行/平台收的款）。
  # 走销售订单这边而不是 ERP 的资金账户接口：业务员没有 ERP 权限，调那边是 403。
  # 只给 id + 名字，不带余额、账号、开户行——录单只需要认出是哪个账户。
  def receipt_accounts
    accounts = Current.account.erp_cash_accounts.where(is_active: true).order(:id).pluck(:id, :name)
    render json: { payload: accounts.map { |id, name| { id: id, name: name } } }
  end

  # 从回收箱恢复（仅管理员/副管）。
  def restore
    order = Current.account.crm_sales_orders.only_deleted.find(params[:id])
    order.restore!
    head :ok
  end

  def attach
    @sales_order.files.attach(params[:files])
    render 'api/v1/accounts/crm/sales_orders/show'
  end

  def detach
    @sales_order.files.find(params[:attachment_id]).purge
    render 'api/v1/accounts/crm/sales_orders/show'
  end

  # 操作历史：订单的创建/编辑记录。
  def audits
    rows = @sales_order.audits.order(created_at: :desc).limit(80).map do |audit|
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

  # 转单预览：把订单明细（自由文本）逐行匹配到产品档案，供转单弹窗带出默认值。
  # 匹配放后端用 SQL 做——产品档案上千条，前端拉一页回来匹配既慢又命中不了。
  # 口径：去空格后全等优先，其次 ILIKE 包含；命中多条时不猜，留空让业务员选。
  def convert_preview
    render json: { payload: Crm::ConvertPreview.new(@sales_order).rows }
  end

  # 回款进度（ERP_SPEC §2.5）：业务员在订单页只读看「应收 / 已收 / 未收 + 下一期到期日」，
  # 催款用。**只透出回款，成本/应付/毛利/账簿一概不给**——销售端与成本硬隔离。
  # 走 CRM 门禁而非 ERP 门禁：业务员本来就没有 ERP 岗位，订单可见性（fetch_sales_order）即是边界。
  # ERP 没上线（总开关关）或这张订单财务还没建账时返回空，前端整块不渲染。
  def receivable_progress
    render json: { payload: Erp::OrderReceivableProgress.new(@sales_order).call }
  end

  # 生产追溯：这张销售订单在 MES 里走过的全程（生产订单 / 阶段时间 / 领料入库出库 / 出货单）。
  # 可见性沿用订单本身（fetch_sales_order 已按 CRM 范围收口）：看得见这张单的人
  # 就看得见它的履约过程，不额外要求 MES 角色——否则业务员查自己的单还得找生产要。
  def production_trace
    render json: { payload: Crm::SalesOrderTraceService.new(account: Current.account, sales_order: @sales_order).call }
  end

  # 转 ERP（金蝶）销售订单：归一化单据 + 还差什么。
  #
  # 只读不落库——业务员先看「能不能推」，缺编码/缺收款方式就地补，补齐再导。
  # 建单时不卡这些（定制编码是下单后工程/采购才给的），卡在这一步。
  def erp_export
    render json: { payload: Crm::ErpOrderExport.new(@sales_order).call }
  end

  private

  # 订单与 PI 只靠 pi_no 字符串挂钩（没有外键），序列化时要带 PI 的抬头/地址/港口。
  # 一次性按号查回来做成 map——逐条 find_by 就是每页一串 N+1。
  # 对不上的订单（生产上 487 填号、只有 106 对得上）map 里没有，jbuilder 按 nil 处理。
  def preload_pis(records = @sales_orders)
    numbers = records.map(&:pi_no).compact_blank.uniq
    @pi_by_no = numbers.empty? ? {} : Current.account.crm_pis.where(pi_no: numbers).index_by(&:pi_no)
    preload_line_item_products(records)
    preload_cash_accounts(records)
  end

  # 收款账户名：订单只存 id，列表要显示名字，一次查完。
  def preload_cash_accounts(records)
    ids = records.filter_map(&:receipt_account_id).uniq
    @cash_account_names = ids.empty? ? {} : Current.account.erp_cash_accounts.where(id: ids).pluck(:id, :name).to_h
  end

  # 明细行只存了 crm_product_id，编码(sku)要去产品档案取。整页的 id 一次查完做成 map。
  def preload_line_item_products(records)
    ids = records.flat_map do |order|
      Array(order.line_items).filter_map { |item| item['crm_product_id'].presence if item.is_a?(Hash) }
    end.uniq
    @product_sku_by_id = ids.empty? ? {} : Current.account.crm_products.where(id: ids).pluck(:id, :sku).to_h
  end

  # 记住「这段客户叫法 → 这个产品」，下次同样文字自动带出。
  # 失败不影响建单：记忆是锦上添花，不该因为它让单建不成。
  def remember_product_choices(items)
    Array(items).each do |item|
      Crm::ProductAlias.remember!(account: Current.account, text: item['name'],
                                  product_id: item['crm_product_id'])
    end
  rescue StandardError => e
    Rails.logger.warn("[产品记忆] 写入失败：#{e.class} #{e.message}")
  end

  # 单条订单也按可见范围收口：业务员只能取本人订单，主管取本团队，管理员取全部。
  # 否则列表虽已隐藏，仍可凭 id 直接 show/update/destroy/attach 越权访问他人订单。
  def fetch_sales_order
    @sales_order = visible_sales_orders.find(params[:id])
  end

  def check_authorization
    authorize(Crm::SalesOrder)
  end

  # 能否删除某订单：负责人本人 或 管理员/副管理员。
  def can_delete_order?(order)
    au = Current.account_user
    au&.administrator? || au&.crm_deputy_admin? || order.owner_id == current_user.id
  end

  # 回收箱条目：够展示 + 恢复即可，轻量 JSON。
  def deleted_order_json(order)
    {
      id: order.id,
      name: order.name,
      order_no: order.order_no,
      customer_name: order.crm_customer&.name,
      amount_micros: order.order_amount_micros,
      currency: order.order_currency,
      owner_name: order.owner&.name,
      deleted_at: order.deleted_at,
      deleted_by_name: order.deleted_by&.name
    }
  end

  # 视图筛选：我的订单、未关联客户（数据兜底）、按状态（生产中…）、按客户。
  # 基础可见范围按部门授权（管理员全部/主管本部门及下级/业务员自己）。
  def filtered_sales_orders
    scope = visible_sales_orders
    scope = scope_docs_mine(scope) if params[:filter] == 'mine'
    scope = scope.where(crm_customer_id: nil) if params[:filter] == 'no_customer'
    apply_order_filters(scope)
  end

  # 视图 tab 计数（我的/全部）：受状态/业务员/月份/搜索约束，但不受 mine 本身约束，
  # 让两个 tab 都能各自显示条数（供页面下划线 tab 上的计数徽章用）。
  def compute_tab_counts
    scope = visible_sales_orders
    scope = scope.where(crm_customer_id: nil) if params[:filter] == 'no_customer'
    base = apply_order_filters(scope)
    @all_count = base.count
    @mine_count = scope_docs_mine(base).count
  end

  ORDER_COLUMN_FILTERS = { status: :status, customer_id: :crm_customer_id, owner_id: :owner_id }.freeze

  def apply_order_filters(scope)
    ORDER_COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = by_month(scope, params[:month]) if params[:month].present?
    scope = search(scope, params[:q]) if params[:q].present?
    scope
  end

  # 销售订单按 CRM 团队收口：业务员看本人，CRM 团队负责人看本团队，管理员/副管理员看全部。
  # 刻意用 CRM 团队（scope_by_team_owner）而非组织部门——与客户/商机的部门口径不同。
  def visible_sales_orders
    scope_docs_for_finance_or(Current.account.crm_sales_orders, team: true)
  end

  # 按下单月份筛选（month 形如 2026-07）；格式非法则忽略。
  def by_month(scope, month)
    start = Date.strptime(month, '%Y-%m').beginning_of_month
    scope.where(order_date: start.beginning_of_day..start.end_of_month.end_of_day)
  rescue ArgumentError
    scope
  end

  # 搜索：订单号 / 订单名称 / 关联客户名（左连避免漏掉未关联客户的订单）。
  def search(scope, query)
    term = "%#{query.strip}%"
    scope.left_joins(:crm_customer)
         .where('crm_sales_orders.order_no ILIKE :t OR crm_sales_orders.name ILIKE :t OR crm_customers.name ILIKE :t', t: term)
  end

  def sales_order_params
    params.require(:sales_order).permit(
      :name, :order_no, :pi_no, :insurance_order_no, :receipt_account_id,
      :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id,
      :status, :order_kind, :order_date, :delivery_date, :order_currency, :exchange_rate, :tax_rate,
      :order_amount_micros, :shipping_micros, :cost_amount_micros, :profit_amount_micros, :profit_rate, :remark,
      :line_items_json,
      :payment_term,
      :source_attachment_id,
      files: []
    )
  end

  # 明细以 JSON 字符串传入（multipart 建单无法带嵌套数组），这里解析成 line_items 数组存 jsonb。
  # 取客户名下的那份 PI 附件（限本客户，避免越权把别人的附件挂过来）。
  def find_source_attachment(attachment_id, customer_id)
    return if attachment_id.blank? || customer_id.blank?

    customer = Current.account.crm_customers.find_by(id: customer_id)
    customer&.files&.find_by(id: attachment_id)
  end

  # 复制 blob 到订单（不搬走客户那份，客户文件页照旧看得到）。
  def copy_source_attachment(attachment)
    return if attachment.blank?

    @sales_order.files.attach(
      io: StringIO.new(attachment.blob.download),
      filename: attachment.blob.filename.to_s,
      content_type: attachment.blob.content_type
    )
  end

  def order_attributes
    attrs = sales_order_params.to_h.symbolize_keys
    json = attrs.delete(:line_items_json)
    attrs[:line_items] = parse_line_items(json) unless json.nil?
    attrs
  end

  def parse_line_items(json)
    items = JSON.parse(json.to_s)
    return [] unless items.is_a?(Array)

    items.filter_map do |item|
      next unless item.is_a?(Hash)

      name = item['name'].to_s.strip
      next if name.blank?

      {
        # 产品档案关联：name 留着客户叫法（PI 上给客户看的还是那串英文），
        # 真正的产品身份靠这个 id——转单/成本归集/毛利都认它。
        'crm_product_id' => item['crm_product_id'].presence&.to_i,
        'name' => name,
        'spec' => item['spec'].to_s.strip,
        'quantity' => item['quantity'],
        'unit_price' => item['unit_price'],
        'amount' => item['amount']
      }
    end
  rescue JSON::ParserError
    []
  end

  def permitted_params
    params.permit(:page, :per_page, :filter, :status, :customer_id, :q, :owner_id, :month)
  end

  # 默认每页 15；调用方可传 per_page 放宽（封顶 200，供 MES 拉销售订单选单器）。
  def results_per_page = permitted_params[:per_page].to_i.then { |n| n.positive? ? [n, 200].min : RESULTS_PER_PAGE }
end
