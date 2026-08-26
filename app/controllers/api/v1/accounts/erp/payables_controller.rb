# 应付台账：按采购单建账（按明细行供应商分组，每供应商一条）或手工建。
class Api::V1::Accounts::Erp::PayablesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_payable, only: [:show, :update, :destroy]

  def index
    scope = filtered_scope
    @payables_count = scope.count
    @summary = { total_micros: scope.sum(:total_amount_micros), paid_micros: scope.sum(:paid_amount_micros) }
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
    @payables = scope.includes(:mes_supplier, :mes_purchase_order).order(:payable_no)
    render 'api/v1/accounts/erp/payables/index_plain'
  end

  # 供应商对账：按供应商汇总应付、已付、未付。
  def supplier_statement
    rows = Current.account.erp_payables.group(:mes_supplier_id)
                  .pluck(:mes_supplier_id, Arel.sql('SUM(total_amount_micros)'), Arel.sql('SUM(paid_amount_micros)'))
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

  def filtered_scope
    scope = Current.account.erp_payables
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(mes_supplier_id: params[:mes_supplier_id]) if params[:mes_supplier_id].present?
    scope = scope.open if params[:open] == 'true'
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
