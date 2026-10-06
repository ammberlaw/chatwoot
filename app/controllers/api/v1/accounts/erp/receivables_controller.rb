# 应收台账：建账（从销售订单一键带入）/ 改账 / 分期计划。
# 已收金额只由核销维护，本控制器的 strong params 不放行。
class Api::V1::Accounts::Erp::ReceivablesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_receivable, only: [:show, :update, :destroy]

  def index
    scope = filtered_scope
    @receivables_count = scope.count
    @summary = {
      total_micros: scope.sum(Arel.sql(Erp::Receivable::BASE_TOTAL_MICROS_SQL)),
      received_micros: scope.sum(Arel.sql(Erp::Receivable::BASE_RECEIVED_MICROS_SQL))
    }
    @receivables = scope.includes(:crm_customer, :crm_sales_order, :owner, :installments)
                        .order(created_at: :desc).page(page_param).per(per_page_param)
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
  def pending_orders
    @orders = pending_order_scope.includes(:crm_customer, :owner).order(order_date: :desc).limit(200)
    @pending_count = pending_order_scope.count
    render 'api/v1/accounts/erp/receivables/pending_orders'
  end

  # 批量建账：只按订单默认口径建（整单一期尾款），要分期的走单张建账。
  # 逐单 rescue——一张失败不该拖垮整批，失败原因原样带回给财务。
  def bulk_build
    orders = pending_order_scope.where(id: Array(params[:crm_sales_order_ids]))
    builder = Erp::LedgerBuilderService.new(Current.account)
    built = []
    failed = []
    orders.each do |order|
      built << builder.from_sales_order(order)
    rescue Erp::LedgerBuilderService::Error, ActiveRecord::RecordInvalid => e
      failed << { order_no: order.order_no, error: e.message }
    end
    render json: { payload: { built_count: built.size, failed: failed } }
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
    render 'api/v1/accounts/erp/receivables/order_detail'
  end

  def aging
    @aging = Erp::AgingService.new(Current.account).receivables(as_of: aging_as_of, basis: aging_basis)
    render 'api/v1/accounts/erp/shared/aging'
  end

  private

  def allocated_change_error
    incoming = receivable_params
    return '已有收款核销的台账不能改币种，请先撤销相关核销' if incoming[:currency].present? && incoming[:currency] != @receivable.currency
    return '已有收款核销的台账不能改客户，请先撤销相关核销' if incoming[:crm_customer_id].present? && incoming[:crm_customer_id].to_i != @receivable.crm_customer_id

    nil
  end

  def filtered_scope
    scope = Current.account.erp_receivables
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_customer_id: params[:crm_customer_id]) if params[:crm_customer_id].present?
    scope = scope.open if params[:open] == 'true'
    return scope if params[:q].blank?

    term = "%#{params[:q].strip}%"
    scope.joins(:crm_customer).where('erp_receivables.receivable_no ILIKE :t OR crm_customers.name ILIKE :t', t: term)
  end

  # 待建账口径：已确认（PENDING_CONFIRMATION 还没确认、CANCELLED 已取消，都不该进应收）
  # 且尚无应收台账的订单。
  UNCONFIRMED_STATUSES = %w[PENDING_CONFIRMATION CANCELLED].freeze

  def pending_order_scope
    built_ids = Current.account.erp_receivables.where.not(crm_sales_order_id: nil).select(:crm_sales_order_id)
    Current.account.crm_sales_orders
           .where.not(status: UNCONFIRMED_STATUSES)
           .where.not(id: built_ids)
  end

  def build_from_order
    order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    Erp::LedgerBuilderService.new(Current.account).from_sales_order(order, installments: installment_specs)
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
