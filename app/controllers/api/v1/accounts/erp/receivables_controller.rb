# 应收台账：建账（从销售订单一键带入）/ 改账 / 分期计划。
# 已收金额只由核销维护，本控制器的 strong params 不放行。
class Api::V1::Accounts::Erp::ReceivablesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_receivable, only: [:show, :update, :destroy, :build_revenue_voucher]

  def index
    scope = filtered_scope
    @receivables_count = scope.count
    @summary = {
      total_micros: scope.sum(Arel.sql(Erp::Receivable::BASE_TOTAL_MICROS_SQL)),
      received_micros: scope.sum(Arel.sql(Erp::Receivable::BASE_RECEIVED_MICROS_SQL))
    }
    @receivables = scope.includes(:crm_customer, :crm_sales_order, :owner, :installments)
                        .order(created_at: :desc).page(page_param).per(per_page_param)
    row_meta = Erp::ReceivableRowMetaService.new(account: Current.account, receivables: @receivables)
    @shipment_meta = row_meta.shipments
    @product_meta = row_meta.products
    @department_names = row_meta.departments
  end

  def show; end

  # 建账：给 crm_sales_order_id 就从订单带入，否则按传入字段手工建。
  def create
    @receivable = if params[:crm_sales_order_id].present?
                    build_from_order
                  else
                    Current.account.erp_receivables.create!(receivable_params)
                  end
    render 'api/v1/accounts/erp/receivables/show'
  rescue Erp::LedgerBuilderService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    # 总额不得改到低于已收：否则未结额变负、状态误判 PAID，与已核销/凭证脱节。
    new_total = receivable_params[:total_amount_micros]
    if new_total.present? && new_total.to_i < @receivable.received_amount_micros.to_i
      return render json: { error: '应收总额不能小于已收金额，请先撤销相关核销' }, status: :unprocessable_entity
    end

    # 币种/客户是核销时校验过的一致性锚点（同币种、同客户才许核）——核销后再改，
    # 已核的钱就挂在错的币种/错的客户上。要改先撤核销。
    if @receivable.allocations.exists? && (guard = allocated_change_error)
      return render json: { error: guard }, status: :unprocessable_entity
    end

    @receivable.update!(receivable_params)
    @receivable.update!(status: @receivable.derived_status)
    render 'api/v1/accounts/erp/receivables/show'
  end

  def destroy
    return render json: { error: '已有收款核销的台账不能删除' }, status: :unprocessable_entity if @receivable.allocations.exists?

    @receivable.destroy!
    head :ok
  end

  # 待核销台账：收款单核销时的候选（同客户、未收清）。
  def open_list
    scope = Current.account.erp_receivables.open
    scope = scope.where(crm_customer_id: params[:crm_customer_id]) if params[:crm_customer_id].present?
    # 只出同币种的候选：核销按原币记账，币种不一致后端会拒，别摆出来让人白选。
    scope = scope.where(currency: params[:currency]) if params[:currency].present?
    @receivables = scope.includes(:crm_customer, :crm_sales_order, :owner).order(:receivable_no)
    render 'api/v1/accounts/erp/receivables/open_list'
  end

  # 待建账订单：已确认但还没建应收的销售订单。
  # 建账是财务确认动作，不做自动建账（金额/币种/分期错了没人知道），改成把漏的摆出来让财务点。
  # 漏建账 = 应收报表少一笔且毫无提示，这个清单就是那个提示。
  # 待建账：原来是 limit(200) 写死、前端也没翻页器——超过 200 张的单在界面上根本看不到，
  # 而页签角标用的是全量 count，于是「角标 318、列表 200」对不上，财务以为系统丢数。
  # 改成真分页，每页与应收台账同样 50 条。
  def pending_orders
    scope = filtered_pending_scope
    @orders = scope.includes(:crm_customer, :owner)
                   .order(order_date: :desc)
                   .page(page_param).per(per_page_param)
    # pending_count 是页签角标，走全量——角标代表「还欠多少张没建」，不该随筛选变。
    # 翻页器用 filtered_count，否则筛完只剩 3 条、翻页器还按 498 条画。
    @pending_count = pending_order_scope.count
    @filtered_count = scope.count
    # 业务员下拉只列「确实有待建账单」的人：全员名单里绝大多数选了是空结果。
    @pending_owners = User.where(id: pending_order_scope.distinct.select(:owner_id)).order(:name)
    @fiscal_start_date = erp_settings.fiscal_start_date
    # 没设启用日时把被挡掉的历史单数量摆出来——否则清单空荡荡，财务不知道是真没有
    # 还是被日切挡住了。
    @before_fiscal_count = @fiscal_start_date ? unfiltered_pending_scope.where(order_date: ...@fiscal_start_date.beginning_of_day).count : 0
    render 'api/v1/accounts/erp/receivables/pending_orders'
  end

  # 批量建账：只按订单默认口径建（整单一期尾款），要分期的走单张建账。
  # 逐单 rescue——一张失败不该拖垮整批，失败原因原样带回给财务。
  def bulk_build
    orders = pending_order_scope.where(id: Array(params[:crm_sales_order_ids]))
    builder = Erp::LedgerBuilderService.new(Current.account)
    built = []
    failed = []
    warnings = []
    orders.each do |order|
      built << builder.from_sales_order(order)
      warnings << builder.voucher_warning if builder.voucher_warning
    rescue Erp::LedgerBuilderService::Error, ActiveRecord::RecordInvalid => e
      failed << { order_no: order.order_no, error: e.message }
    end
    render json: { payload: { built_count: built.size, failed: failed, voucher_warnings: warnings } }
  end

  # 补出收入凭证：建账时该出没出的（规则上线前建的老账、或当时订单还没发货），
  # 财务在台账上点一下补。分录与建账时那张完全一致，并且挂回这条台账上——
  # 手工录的凭证挂不上来源，台账的「收入凭证」列会一直空着。
  def build_revenue_voucher
    service = Erp::AutoVoucherService.new(Current.account)
    if (blocker = service.revenue_voucher_blocker(@receivable))
      return render json: { error: "出不了收入凭证：#{blocker}" }, status: :unprocessable_entity
    end

    service.for_receivable_revenue(@receivable)
    render 'api/v1/accounts/erp/receivables/show'
  rescue ActiveRecord::RecordInvalid => e
    # 典型是收入确认日落在已结账期间——凭证模型那层拒掉，原话比什么都清楚。
    # 取 full_messages 而非 e.message：后者带一层「验证失败：」前缀，跟这里的前缀叠起来啰嗦。
    render json: { error: "出不了收入凭证：#{e.record.errors.full_messages.to_sentence}" },
           status: :unprocessable_entity
  end

  # 账龄分析：basis=due 逾期账龄 / basis=invoice 账龄（按建账日）。
  # 销售订单详情（财务侧）：订单明细（出了什么货、单价多少）+ 挂着的 CRM/MES 单据。
  #
  # 为什么不复用 crm/sales_orders 那套接口：财务多半没有 crm_role（can_access_crm? 为假），
  # 走 CRM 门禁一律 403——财务查应收对应的那张订单是本职工作，不该为此给他开 CRM 角色。
  # 这里由 ERP 门禁放行，服务端复用同一个追溯服务，口径与 CRM 侧一致。
  def order_detail
    @order = Current.account.crm_sales_orders
                    .includes(:crm_customer, :owner, :crm_opportunity)
                    .find(params[:crm_sales_order_id])
    @trace = Crm::SalesOrderTraceService.new(account: Current.account, sales_order: @order).call
    @order_receivable = Current.account.erp_receivables.find_by(crm_sales_order_id: @order.id)
    @line_items_with_sku = line_items_with_sku(@order)
    render 'api/v1/accounts/erp/receivables/order_detail'
  end

  def aging
    @aging = Erp::AgingService.new(Current.account).receivables(as_of: aging_as_of, basis: aging_basis)
    render 'api/v1/accounts/erp/shared/aging'
  end

  private

  # 明细里只有 crm_product_id，编码要去产品档案取（一张单的几行，一次查完）。
  def line_items_with_sku(order)
    items = Array(order.line_items)
    ids = items.filter_map { |item| item['crm_product_id'].presence if item.is_a?(Hash) }
    skus = ids.empty? ? {} : Current.account.crm_products.where(id: ids).pluck(:id, :sku).to_h
    items.map { |item| item.is_a?(Hash) ? item.merge('sku' => skus[item['crm_product_id'].presence&.to_i]) : item }
  end

  def allocated_change_error
    incoming = receivable_params
    return '已有收款核销的台账不能改币种，请先撤销相关核销' if incoming[:currency].present? && incoming[:currency] != @receivable.currency
    return '已有收款核销的台账不能改客户，请先撤销相关核销' if incoming[:crm_customer_id].present? && incoming[:crm_customer_id].to_i != @receivable.crm_customer_id

    nil
  end

  # 单据日期：与台账上「单据日期」那一列同一个口径——首次出库日（账期从货走那天起算），
  # 没出货的老单回落到建账日期。两处口径必须一样，否则按日期一筛，
  # 列表上明明写着 10-08 的单却筛不出来。
  DOC_DATE_SQL = <<~SQL.squish
    COALESCE(
      (SELECT MIN(s.shipped_at)::date FROM mes_shipments s
        WHERE s.crm_sales_order_id = erp_receivables.crm_sales_order_id
          AND s.shipped_at IS NOT NULL),
      erp_receivables.created_at::date
    )
  SQL

  # 单据日期区间，单边留空＝只卡一头。
  def doc_date_scope(scope)
    scope = scope.where("#{DOC_DATE_SQL} >= ?", params[:from]) if params[:from].present?
    scope = scope.where("#{DOC_DATE_SQL} <= ?", params[:to]) if params[:to].present?
    scope
  end

  LEDGER_FILTERS = { status: :status, crm_customer_id: :crm_customer_id }.freeze

  # 表头漏斗能筛哪几列（列名 → SQL）。只列能落到真实字段上的：
  # 商品编码/品名/规格/数量/单价那些摊在订单 line_items 这个 JSON 里，没法按列筛；
  # 单据日期/编号/仓库来自出库单（子查询拼的），也不在这儿。
  # ⚠️ 前端 LEDGER_COLUMN_DEFS 里标了 filter 的列必须和这张表对齐，否则漏斗点了没反应。
  LEDGER_COLUMN_SQL = {
    'orderNo' => 'crm_sales_orders.order_no',
    'piNo' => 'crm_sales_orders.pi_no',
    'insuranceNo' => 'crm_sales_orders.insurance_order_no',
    'customerCode' => 'crm_customers.customer_code',
    'customer' => 'crm_customers.name',
    'owner' => "COALESCE(NULLIF(users.crm_name, ''), users.name)",
    'currency' => 'erp_receivables.currency',
    'status' => 'erp_receivables.status',
    'orderStatus' => 'crm_sales_orders.status'
  }.freeze

  def filtered_scope
    scope = Current.account.erp_receivables
    LEDGER_FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = scope.open if params[:open] == 'true'
    scope = keyword_scope(doc_date_scope(scope))
    return scope if params[:cf].blank?

    # 漏斗筛的列散在三张关联表上，有筛才 join——不筛时别白白拖三张表。
    apply_column_filters(
      scope.left_joins(:crm_customer, :owner).left_joins(:crm_sales_order), LEDGER_COLUMN_SQL
    )
  end

  def keyword_scope(scope)
    return scope if params[:q].blank?

    term = "%#{params[:q].strip}%"
    scope.joins(:crm_customer).where('erp_receivables.receivable_no ILIKE :t OR crm_customers.name ILIKE :t', t: term)
  end

  # 待建账口径（已确认、尚无应收台账、会计启用日之后）收在 Erp::OpeningReadiness 里：
  # 财务看板的「待建账」数用的是同一个 scope，两处各写一份早晚对不上。
  #
  # 会计启用日之前的单不进待建账：那些是迁移进来的历史单（上线时一次性导入的
  # 已完结订单），钱早收完了，建出来全是假应收——这个清单一度列着 484 张
  # 2227 万的历史单，批量点下去就是一场事故。日切前的余额走期初建账一笔进总账。
  # 启用日未设＝不切（沿用旧行为），设置页会提示去设。
  def readiness
    @readiness ||= Erp::OpeningReadiness.new(Current.account)
  end

  def pending_order_scope
    readiness.pending_order_scope
  end

  def unfiltered_pending_scope
    readiness.unfiltered_pending_scope
  end

  # 待建账的查找条件：关键字（订单号 / PI 号 / 客户名）、业务员、订单状态。
  # 498 张单摆在一页上，财务要找某一张只能靠浏览器查找——这几个条件就是为此补的。
  def filtered_pending_scope
    scope = pending_order_scope
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    pending_keyword_scope(pending_date_scope(scope))
  end

  # 按下单日期筛（台账那边筛的是单据日期，这边还没建账、只有下单日期这个口径）。
  def pending_date_scope(scope)
    scope = scope.where(order_date: params[:from].to_date.beginning_of_day..) if params[:from].present?
    scope = scope.where(order_date: ..params[:to].to_date.end_of_day) if params[:to].present?
    scope
  end

  def pending_keyword_scope(scope)
    return scope if params[:q].blank?

    term = "%#{params[:q].to_s.strip}%"
    scope.left_joins(:crm_customer)
         .where('crm_sales_orders.order_no ILIKE :t OR crm_sales_orders.pi_no ILIKE :t ' \
                'OR crm_sales_orders.name ILIKE :t OR crm_customers.name ILIKE :t', t: term)
  end

  def erp_settings
    @erp_settings ||= Erp::Setting.for_account(Current.account)
  end

  def build_from_order
    order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    builder = Erp::LedgerBuilderService.new(Current.account)
    receivable = builder.from_sales_order(order, installments: installment_specs)
    @voucher_warning = builder.voucher_warning
    receivable
  end

  def installment_specs
    Array(params[:installments]).map do |spec|
      spec.permit(:kind, :amount_micros, :due_basis, :due_days, :due_date, :remark).to_h.symbolize_keys
    end
  end

  def fetch_receivable
    @receivable = Current.account.erp_receivables.includes(:installments).find(params[:id])
  end

  def check_authorization
    authorize(Erp::Receivable)
  end

  def receivable_params
    params.require(:receivable).permit(
      :crm_customer_id, :crm_sales_order_id, :currency, :exchange_rate, :total_amount_micros, :owner_id, :remark,
      installments_attributes: [:id, :seq, :kind, :amount_micros, :due_basis, :due_days, :due_date, :remark, :_destroy]
    )
  end
end
