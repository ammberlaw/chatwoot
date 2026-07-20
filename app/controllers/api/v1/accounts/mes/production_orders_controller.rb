class Api::V1::Accounts::Mes::ProductionOrdersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_production_order, only: [:show, :update, :destroy, :attach, :detach, :audits]

  COLUMN_FILTERS = { stage: :stage, status: :status, crm_sales_order_id: :crm_sales_order_id, owner_id: :owner_id }.freeze

  def index
    scope = Current.account.mes_production_orders
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = scope.where('order_no ILIKE :t OR product_name ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @production_orders_count = scope.count
    @production_orders = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @production_order = Current.account.mes_production_orders.create!(
      production_order_params.merge(owner_id: production_order_params[:owner_id] || current_user.id)
    )
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 从销售订单一键转生产订单（脊柱起点）。成品/数量优先取参数，缺则从销售订单带默认。
  def convert
    sales_order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    product = Current.account.crm_products.find_by(id: params[:crm_product_id])
    @production_order = Current.account.mes_production_orders.create!(
      crm_sales_order: sales_order,
      crm_product: product,
      product_name: params[:product_name].presence || product&.name,
      qty: params[:qty],
      unit: params[:unit],
      delivery_date: params[:delivery_date].presence || sales_order.delivery_date,
      owner_id: params[:owner_id] || current_user.id
    )
    render 'api/v1/accounts/mes/production_orders/show'
  end

  def update
    @production_order.update!(production_order_params)
    render 'api/v1/accounts/mes/production_orders/show'
  end

  def destroy
    @production_order.destroy!
    head :ok
  end

  def attach
    @production_order.files.attach(params[:files])
    render 'api/v1/accounts/mes/production_orders/show'
  end

  def detach
    @production_order.files.find(params[:attachment_id]).purge
    render 'api/v1/accounts/mes/production_orders/show'
  end

  def audits
    rows = @production_order.audits.order(created_at: :desc).limit(80).map do |audit|
      {
        id: audit.id,
        action: audit.action,
        changed_fields: audit.audited_changes.keys,
        user_name: audit.user&.name || '系统',
        created_at: audit.created_at
      }
    end
    render json: { payload: rows }
  end

  private

  def fetch_production_order
    @production_order = Current.account.mes_production_orders.find(params[:id])
  end

  def check_authorization
    authorize(Mes::ProductionOrder)
  end

  def production_order_params
    params.require(:production_order).permit(
      :crm_sales_order_id, :crm_product_id, :product_name, :qty, :unit, :produced_qty,
      :bom_id, :stage, :status, :delivery_date, :planned_start_date, :planned_end_date,
      :actual_start_date, :actual_end_date, :owner_id, :remark, files: []
    )
  end
end
