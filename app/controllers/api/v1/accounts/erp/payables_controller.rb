# 应付台账：按采购单建账（按明细行供应商分组，每供应商一条）或手工建。
class Api::V1::Accounts::Erp::PayablesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_payable, only: [:show, :update, :destroy, :detail]

  def index
    scope = filtered_scope
    @payables_count = scope.count
    @summary = { total_micros: scope.sum(Arel.sql(Erp::Payable::BASE_TOTAL_MICROS_SQL)),
                 paid_micros: scope.sum(Arel.sql(Erp::Payable::BASE_PAID_MICROS_SQL)) }
    @payables = scope.includes(:mes_supplier,
                               mes_purchase_order: { purchase_items: [:mes_material, :crm_product] })
                     .order(created_at: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  # 台账明细弹窗：点台账单号就地看这笔应付到底是哪张采购单、哪几行料、收没收到货、付了几次。
  # 和应收台账的订单详情同一个用法——财务核账时不想跳去 MES（多半也没有 MES 身份）。
  def detail
    po = @payable.mes_purchase_order
    # 一张采购单可能含多家供应商，这笔应付只认本供应商那几行（口径与台账列表同一个）。
    @detail_items = @payable.supplier_items
    # 入库单带上明细行与仓库：财务点开要看「这张单到底收了什么、多少」，
    # 否则只有单号和过账日期，还得自己去 MES 翻。
    @detail_entries = if po
                        Current.account.mes_stock_entries.where(purchase_order_id: po.id)
                               .includes(stock_entry_items: %i[mes_material crm_product]).order(:id)
                      else
                        []
                      end
    # Mes::StockEntry 上没有 warehouse 关联，只有裸的 from/to_warehouse_id 列
    # （同 Crm::SalesOrderTraceService 那边的注释）。一次读成 id→名字，别逐条查。
    @warehouse_names = Current.account.mes_warehouses.pluck(:id, :name).to_h
    @detail_allocations = @payable.allocations
                                  .includes(payment_record: :cash_account).order(:id)
    render 'api/v1/accounts/erp/payables/detail'
  end

  # 该出没出应付凭证的入库单（规则上线前过的账、或当时科目没配齐）。
  # 应付的凭证不在这张台账上生成——它是原料入库**过账时**自动出的（借存货/贷应付）。
  # 规则 2026-10-09 才上线，在那之前过账的单一张凭证都没有，而台账上又没有任何补出的
  # 入口：财务看到的就是「应付有账、总账没账」，还问不出为什么。这里把名单和原因一起给出来。
  def pending_vouchers
    service = Erp::AutoVoucherService.new(Current.account)
    rows = unvouchered_receipts.map do |entry|
      { id: entry.id, entry_no: entry.entry_no, purpose: entry.purpose, posted_on: entry.posted_at&.to_date,
        po_no: entry.purchase_order&.po_no, blocker: service.stock_receipt_voucher_blocker(entry) }
    end
    render json: { payload: rows, count: rows.size }
  end

  # 补出一张入库单的应付凭证。出不了就把原因原样返回，不留「点了没动静」。
  def build_receipt_voucher
    entry = Current.account.mes_stock_entries.find(params[:stock_entry_id])
    service = Erp::AutoVoucherService.new(Current.account)
    if (blocker = service.stock_receipt_voucher_blocker(entry))
      return render json: { error: "出不了应付凭证：#{blocker}" }, status: :unprocessable_entity
    end

    service.for_stock_receipt(entry)
    render json: { payload: { stock_entry_id: entry.id, entry_no: entry.entry_no,
                              voucher_no: service.stock_receipt_voucher(entry)&.voucher_no } }
  rescue ActiveRecord::RecordInvalid => e
    # 典型是凭证日期落在已结账期间——凭证模型那层拒掉，原话比什么都清楚（同应收那边）。
    render json: { error: "出不了应付凭证：#{e.record.errors.full_messages.to_sentence}" },
           status: :unprocessable_entity
  end

  def create
    if params[:mes_purchase_order_id].present?
      purchase_order = Current.account.mes_purchase_orders.find(params[:mes_purchase_order_id])
      @payables = Erp::LedgerBuilderService.new(Current.account).from_purchase_order(purchase_order)
      return render json: { error: '该采购单的应付已全部建过账' }, status: :unprocessable_entity if @payables.empty?

      render 'api/v1/accounts/erp/payables/index_plain'
    else
      @payable = Current.account.erp_payables.create!(payable_params)
      render 'api/v1/accounts/erp/payables/show'
    end
  rescue Erp::LedgerBuilderService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    # 总额不得改到低于已付：否则未结额变负、状态误判、与已核销/凭证脱节。
    new_total = payable_params[:total_amount_micros]
    if new_total.present? && new_total.to_i < @payable.paid_amount_micros.to_i
      return render json: { error: '应付总额不能小于已付金额，请先撤销相关核销' }, status: :unprocessable_entity
    end

    # 币种/供应商是核销时校验过的一致性锚点，核销后不许再改（同应收侧）。
    if @payable.allocations.exists? && (guard = allocated_change_error)
      return render json: { error: guard }, status: :unprocessable_entity
    end

    @payable.update!(payable_params)
    @payable.update!(status: @payable.derived_status)
    render 'api/v1/accounts/erp/payables/show'
  end

  def destroy
    return render json: { error: '已有付款核销的台账不能删除' }, status: :unprocessable_entity if @payable.allocations.exists?

    @payable.destroy!
    head :ok
  end

  def open_list
    scope = Current.account.erp_payables.open
    scope = scope.where(mes_supplier_id: params[:mes_supplier_id]) if params[:mes_supplier_id].present?
    # 只出同币种的候选（同上）。
    scope = scope.where(currency: params[:currency]) if params[:currency].present?
    @payables = scope.includes(:mes_supplier, :mes_purchase_order).order(:payable_no)
    render 'api/v1/accounts/erp/payables/index_plain'
  end

  # 供应商对账：按供应商汇总应付、已付、未付。
  def supplier_statement
    # 同一个供应商可能既有美元应付又有人民币应付，必须各自折本位币再加。
    rows = Current.account.erp_payables.group(:mes_supplier_id)
                  .pluck(:mes_supplier_id,
                         Arel.sql("SUM(#{Erp::Payable::BASE_TOTAL_MICROS_SQL})"),
                         Arel.sql("SUM(#{Erp::Payable::BASE_PAID_MICROS_SQL})"))
    names = Current.account.mes_suppliers.where(id: rows.map(&:first)).pluck(:id, :name).to_h
    mapped = rows.map do |supplier_id, total, paid|
      { id: supplier_id, name: names[supplier_id], total_micros: total.to_i, paid_micros: paid.to_i,
        outstanding_micros: total.to_i - paid.to_i }
    end
    @rows = mapped.sort_by { |row| -row[:outstanding_micros] }
    render 'api/v1/accounts/erp/payables/supplier_statement'
  end

  # 账龄分析：basis=due 逾期账龄 / basis=invoice 账龄（按建账日）。
  def aging
    @aging = Erp::AgingService.new(Current.account).payables(as_of: aging_as_of, basis: aging_basis)
    render 'api/v1/accounts/erp/shared/aging'
  end

  # 按月未付：截止某月末，还欠哪些供应商各多少，对公/对私分行，欠的是哪几个月的货。
  def monthly
    @monthly = Erp::PayableMonthlyService.new(
      account: Current.account, as_of: params[:as_of],
      months: params[:months].presence || Erp::PayableMonthlyService::DEFAULT_MONTHS,
      supplier_id: params[:mes_supplier_id]
    ).call
    render 'api/v1/accounts/erp/payables/monthly'
  end

  private

  FILTER_COLUMNS = { status: :status, mes_supplier_id: :mes_supplier_id, currency: :currency,
                     settle_type: :settle_type }.freeze

  # 发生日期：incurred_on 是「货到那天」，没填的老单回落到建账日期。
  # 与按月未付表（Erp::PayableMonthlyService）用同一个表达式，两处数才对得上。
  INCURRED_ON_SQL = 'COALESCE(erp_payables.incurred_on, erp_payables.created_at::date)'.freeze

  # 本条台账对应的采购明细（同一供应商那几行）拼成一串，按「任一行命中」筛。
  # 一条应付挂多行料，财务搜某颗料是为了找「哪几张应付里有它」。
  SUPPLIER_ITEM_SQL = lambda { |field|
    <<~SQL.squish
      (SELECT string_agg(#{field}, ' ') FROM mes_purchase_items pi
        LEFT JOIN mes_materials m ON m.id = pi.mes_material_id
        LEFT JOIN crm_products p ON p.id = pi.crm_product_id
        WHERE pi.purchase_order_id = erp_payables.mes_purchase_order_id
          AND pi.mes_supplier_id IS NOT DISTINCT FROM erp_payables.mes_supplier_id)
    SQL
  }

  # 表头漏斗能筛哪几列（列名 → SQL）。
  # ⚠️ 前端 LEDGER_COLUMN_DEFS 里标了 filter 的列必须和这张表对齐，否则漏斗点了没反应。
  LEDGER_COLUMN_SQL = {
    'no' => 'erp_payables.payable_no',
    # 供应商那一格同时显示供应商名和采购单号，两样都能搜到才对得上眼睛看到的。
    'supplier' => "CONCAT_WS(' ', mes_suppliers.name, mes_purchase_orders.po_no)",
    'code' => SUPPLIER_ITEM_SQL.call('COALESCE(p.sku, m.material_no)'),
    'name' => SUPPLIER_ITEM_SQL.call('COALESCE(p.name, m.name)'),
    'spec' => SUPPLIER_ITEM_SQL.call('COALESCE(m.specification, p.specification)'),
    'settle' => 'erp_payables.settle_type',
    'status' => 'erp_payables.status'
  }.freeze

  def filtered_scope
    scope = Current.account.erp_payables
    FILTER_COLUMNS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = scope.open if params[:open] == 'true'
    scope = keyword_scope(date_scope(scope))
    return scope if params[:cf].blank?

    apply_column_filters(scope.left_joins(:mes_supplier, :mes_purchase_order), LEDGER_COLUMN_SQL)
  end

  # 按发生日期筛，起止都可单边留空（只填起＝该日之后全部）。
  def date_scope(scope)
    scope = scope.where("#{INCURRED_ON_SQL} >= ?", params[:from]) if params[:from].present?
    scope = scope.where("#{INCURRED_ON_SQL} <= ?", params[:to]) if params[:to].present?
    scope
  end

  def keyword_scope(scope)
    return scope if params[:q].blank?

    term = "%#{params[:q].strip}%"
    # 采购单号也能搜：供应商交货、仓库入库、财务对账都认那个号，查应付时手上拿的就是它。
    scope.joins(:mes_supplier).left_joins(:mes_purchase_order)
         .where('erp_payables.payable_no ILIKE :t OR mes_suppliers.name ILIKE :t ' \
                'OR mes_purchase_orders.po_no ILIKE :t', t: term)
  end

  # 已过账、按口径该出应付凭证、但一张也没出的入库单（采购入库 / 采购退货）。
  def unvouchered_receipts
    issued = Current.account.erp_vouchers.where(source_type: 'Mes::StockEntry').select(:source_id)
    Current.account.mes_stock_entries
           .where(purpose: Mes::StockEntry::PAYABLE_VOUCHER_PURPOSES, status: 'POSTED')
           .where.not(id: issued).includes(:purchase_order).order(:posted_at, :id)
  end

  def fetch_payable
    @payable = Current.account.erp_payables.find(params[:id])
  end

  def check_authorization
    authorize(Erp::Payable)
  end

  def allocated_change_error
    incoming = payable_params
    return '已有付款核销的台账不能改币种，请先撤销相关核销' if incoming[:currency].present? && incoming[:currency] != @payable.currency
    return '已有付款核销的台账不能改供应商，请先撤销相关核销' if incoming[:mes_supplier_id].present? && incoming[:mes_supplier_id].to_i != @payable.mes_supplier_id

    nil
  end

  def payable_params
    params.require(:payable).permit(
      :mes_supplier_id, :mes_purchase_order_id, :currency, :exchange_rate, :total_amount_micros, :due_date, :remark,
      # 结算方式默认按供应商档案带出，个别单实际开没开票不一样，财务在台账上直接改。
      :settle_type
    )
  end
end
