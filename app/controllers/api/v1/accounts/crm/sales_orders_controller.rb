class Api::V1::Accounts::Crm::SalesOrdersController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_sales_order, only: [:show, :update, :destroy, :attach, :detach, :audits]

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
        user_name: audit.user&.name || audit.username || '系统',
        created_at: audit.created_at
      }
    end
    render json: { payload: rows }
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
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    scope = by_month(scope, params[:month]) if params[:month].present?
    scope = search(scope, params[:q]) if params[:q].present?
    scope
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
      :name, :order_no, :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id,
      :status, :order_date, :delivery_date, :order_currency, :exchange_rate,
      :order_amount_micros, :cost_amount_micros, :profit_amount_micros, :profit_rate, :remark,
      files: []
    )
  end

  def permitted_params
    params.permit(:page, :filter, :status, :customer_id, :q, :owner_id, :month)
  end
end
