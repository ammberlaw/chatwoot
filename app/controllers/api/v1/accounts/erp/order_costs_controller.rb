# 订单成本归集与毛利报表。成本/毛利是权限墙核心区，只在 ERP 内可见。
class Api::V1::Accounts::Erp::OrderCostsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_cost, only: [:update, :destroy]

  def index
    scope = Current.account.erp_order_costs.includes(:crm_sales_order, :mes_supplier, :created_by)
    scope = scope.where(crm_sales_order_id: params[:crm_sales_order_id]) if params[:crm_sales_order_id].present?
    scope = scope.where(cost_type: params[:cost_type]) if params[:cost_type].present?
    @costs = scope.order(created_at: :desc).limit(200)
  end

  def create
    @cost = Current.account.erp_order_costs.new(cost_params)
    @cost.created_by_id = current_user.id
    @cost.save!
    render 'api/v1/accounts/erp/order_costs/show'
  end

  def update
    @cost.update!(cost_params)
    render 'api/v1/accounts/erp/order_costs/show'
  end

  def destroy
    @cost.destroy!
    head :ok
  end

  # 毛利报表：订单维度 + 业务员/客户汇总。
  def margin
    service = Erp::MarginService.new(Current.account)
    @rows = service.by_order(from: params[:from], to: params[:to])
    @summary_by = params[:group_by].presence
    @summary = @summary_by ? service.summary_by(@summary_by, from: params[:from], to: params[:to]) : []
    render 'api/v1/accounts/erp/order_costs/margin'
  end

  private

  def fetch_cost
    @cost = Current.account.erp_order_costs.find(params[:id])
  end

  def check_authorization
    authorize(Erp::OrderCost)
  end

  def cost_params
    params.require(:order_cost).permit(
      :crm_sales_order_id, :cost_type, :amount_micros, :currency, :exchange_rate,
      :happened_at, :mes_supplier_id, :remark
    )
  end
end
