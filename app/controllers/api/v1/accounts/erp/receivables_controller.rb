# 应收台账：建账（从销售订单一键带入）/ 改账 / 分期计划。
# 已收金额只由核销维护，本控制器的 strong params 不放行。
class Api::V1::Accounts::Erp::ReceivablesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_receivable, only: [:show, :update, :destroy]

  def index
    scope = filtered_scope
    @receivables_count = scope.count
    @summary = {
      total_micros: scope.sum(:total_amount_micros),
      received_micros: scope.sum(:received_amount_micros)
    }
    @receivables = scope.includes(:crm_customer, :crm_sales_order, :owner, :installments)
                        .order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
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
    @receivables = scope.includes(:crm_customer, :crm_sales_order).order(:receivable_no)
    render 'api/v1/accounts/erp/receivables/open_list'
  end

  # 账龄分析：basis=due 逾期账龄 / basis=invoice 账龄（按建账日）。
  def aging
    @aging = Erp::AgingService.new(Current.account).receivables(as_of: aging_as_of, basis: aging_basis)
    render 'api/v1/accounts/erp/shared/aging'
  end

  private

  def filtered_scope
    scope = Current.account.erp_receivables
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_customer_id: params[:crm_customer_id]) if params[:crm_customer_id].present?
    scope = scope.open if params[:open] == 'true'
    return scope if params[:q].blank?

    term = "%#{params[:q].strip}%"
    scope.joins(:crm_customer).where('erp_receivables.receivable_no ILIKE :t OR crm_customers.name ILIKE :t', t: term)
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
