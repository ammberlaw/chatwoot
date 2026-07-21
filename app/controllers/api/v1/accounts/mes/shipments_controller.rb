class Api::V1::Accounts::Mes::ShipmentsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_shipment, only: [:show, :update, :destroy, :notify, :ship]

  def index
    scope = Current.account.mes_shipments
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_sales_order_id: params[:crm_sales_order_id]) if params[:crm_sales_order_id].present?
    @shipments_count = scope.count
    @shipments = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @shipment = Current.account.mes_shipments.create!(
      shipment_params.merge(owner_id: shipment_params[:owner_id] || current_user.id)
    )
    render 'api/v1/accounts/mes/shipments/show'
  end

  def update
    @shipment.update!(shipment_params)
    render 'api/v1/accounts/mes/shipments/show'
  end

  def destroy
    @shipment.destroy!
    head :ok
  end

  # 通知出库（XMind 节点8）。
  def notify
    @shipment.notify!
    render 'api/v1/accounts/mes/shipments/show'
  end

  # 出库：扣成品库存 + 回写销售订单已出货。
  def ship
    @shipment.ship!
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_shipment
    @shipment = Current.account.mes_shipments.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Shipment)
  end

  def shipment_params
    params.require(:shipment).permit(
      :crm_sales_order_id, :crm_customer_id, :production_order_id, :warehouse_id, :owner_id, :remark,
      shipment_items_attributes: [:id, :crm_product_id, :qty, :unit, :remark, :_destroy]
    )
  end
end
