# 应付台账：按采购单建账（按明细行供应商分组，每供应商一条）或手工建。
class Api::V1::Accounts::Erp::PayablesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_payable, only: [:show, :update, :destroy]

  def index
    scope = filtered_scope
    @payables_count = scope.count
    @summary = { total_micros: scope.sum(Arel.sql(Erp::Payable::BASE_TOTAL_MICROS_SQL)),
                 paid_micros: scope.sum(Arel.sql(Erp::Payable::BASE_PAID_MICROS_SQL)) }
    @payables = scope.includes(:mes_supplier, :mes_purchase_order)
                     .order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

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

  private

  FILTER_COLUMNS = { status: :status, mes_supplier_id: :mes_supplier_id, currency: :currency }.freeze

  def filtered_scope
    scope = Current.account.erp_payables
    FILTER_COLUMNS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = scope.open if params[:open] == 'true'
    keyword_scope(scope)
  end

  def keyword_scope(scope)
    return scope if params[:q].blank?

    term = "%#{params[:q].strip}%"
    scope.joins(:mes_supplier).where('erp_payables.payable_no ILIKE :t OR mes_suppliers.name ILIKE :t', t: term)
  end

  def fetch_payable
    @payable = Current.account.erp_payables.find(params[:id])
  end

  def check_authorization
    authorize(Erp::Payable)
  end

  def payable_params
    params.require(:payable).permit(
      :mes_supplier_id, :mes_purchase_order_id, :currency, :exchange_rate, :total_amount_micros, :due_date, :remark
    )
  end
end
