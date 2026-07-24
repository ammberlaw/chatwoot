class Api::V1::Accounts::Mes::PurchaseOrdersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_purchase_order, only: [:show, :update, :destroy]

  COLUMN_FILTERS = { status: :status, production_order_id: :production_order_id }.freeze

  def index
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_purchase_orders))
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = scope.where(has_exception: true) if params[:exception] == 'true'
    scope = scope.where('po_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @purchase_orders_count = scope.count
    @purchase_orders = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @purchase_order = Current.account.mes_purchase_orders.new(
      purchase_order_params.merge(owner_id: purchase_order_params[:owner_id] || current_user.id)
    )
    @purchase_order.fallback_product_line = current_product_line
    @purchase_order.save!
    render 'api/v1/accounts/mes/purchase_orders/show'
  end

  def update
    @purchase_order.update!(purchase_order_params)
    render 'api/v1/accounts/mes/purchase_orders/show'
  end

  def destroy
    @purchase_order.destroy!
    head :ok
  end

  # BOM 算料：按生产订单的 BOM 展开采购需求，供采购单预填。
  def requirement
    production_order = Current.account.mes_production_orders.find(params[:production_order_id])
    render json: { payload: production_order.material_requirements }
  end

  private

  def fetch_purchase_order
    @purchase_order = Current.account.mes_purchase_orders.find(params[:id])
  end

  def check_authorization
    authorize(Mes::PurchaseOrder)
  end

  def purchase_order_params
    params.require(:purchase_order).permit(
      :production_order_id, :status, :expected_date, :follow_up_date,
      :has_exception, :exception_note, :owner_id, :remark,
      purchase_items_attributes: [
        :id, :item_type, :mes_material_id, :crm_product_id, :mes_supplier_id, :arrival_date,
        :qty, :unit, :rate_micros, :received_qty, :remark, :_destroy
      ]
    )
  end
end
