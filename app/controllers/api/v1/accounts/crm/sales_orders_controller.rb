class Api::V1::Accounts::Crm::SalesOrdersController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_sales_order, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 15

  def index
    @sales_orders_scope = filtered_sales_orders
    @sales_orders_count = @sales_orders_scope.count
    @sales_orders = @sales_orders_scope
                    .order(order_date: :desc)
                    .page(permitted_params[:page] || 1)
                    .per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @sales_order = Current.account.crm_sales_orders.create!(sales_order_params.merge(owner_id: sales_order_params[:owner_id] || current_user.id))
  end

  def update
    @sales_order.update!(sales_order_params)
  end

  def destroy
    @sales_order.destroy!
    head :ok
  end

  private

  def fetch_sales_order
    @sales_order = Current.account.crm_sales_orders.find(params[:id])
  end

  def check_authorization
    authorize(Crm::SalesOrder)
  end

  # 视图筛选：我的订单、未关联客户（数据兜底）、按状态（生产中…）、按客户。
  def filtered_sales_orders
    scope = Current.account.crm_sales_orders
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(crm_customer_id: nil) if params[:filter] == 'no_customer'
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope
  end

  def sales_order_params
    params.require(:sales_order).permit(
      :name, :order_no, :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id,
      :status, :order_date, :delivery_date, :order_currency, :exchange_rate,
      :order_amount_micros, :cost_amount_micros, :profit_amount_micros, :profit_rate, :remark
    )
  end

  def permitted_params
    params.permit(:page, :filter, :status, :customer_id)
  end
end
