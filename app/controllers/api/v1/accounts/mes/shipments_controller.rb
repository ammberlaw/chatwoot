class Api::V1::Accounts::Mes::ShipmentsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_shipment, only: [:show, :update, :destroy, :notify, :ship, :submit, :approve, :reject]

  COLUMN_FILTERS = { status: :status, kind: :kind, crm_sales_order_id: :crm_sales_order_id }.freeze

  def index
    scope = scoped_by_product_line(Current.account.mes_shipments)
    COLUMN_FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = scope_visible(scope)
    @shipments_count = scope.count
    @shipments = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  # 现货出库单由 CRM 业务条线开单（无出库能力者一律记为 STOCK，开单即进入审核）。
  def create
    stock = shipment_params[:kind] == 'STOCK' || !Current.account_user.mes_can?(:shipment)
    @shipment = Current.account.mes_shipments.new(
      shipment_params.merge(owner_id: shipment_params[:owner_id] || current_user.id, kind: stock ? 'STOCK' : 'PRODUCTION')
    )
    @shipment.fallback_product_line = current_product_line
    @shipment.save!
    @shipment.submit_for_approval!(current_user) if @shipment.stock?
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

  # 业务员改单后重新提交审核（驳回态）。
  def submit
    return render json: { error: '只有开单人可提交审核' }, status: :forbidden unless @shipment.owner_id == current_user.id || admin_like?

    @shipment.submit_for_approval!(current_user)
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 主管审核通过 → 推仓库。
  def approve
    return render json: { error: '无权审核该出库单' }, status: :forbidden unless can_approve_shipment?(@shipment)

    @shipment.approve!(current_user)
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 主管驳回 → 退回业务员（需填原因）。
  def reject
    return render json: { error: '无权审核该出库单' }, status: :forbidden unless can_approve_shipment?(@shipment)

    reason = params[:reason].to_s.strip
    return render json: { error: '请填写驳回原因' }, status: :unprocessable_entity if reason.blank?

    @shipment.reject!(current_user, reason: reason)
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 出库：扣成品库存 + 回写销售订单已出货。
  def ship
    @shipment.ship!
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 待我审核：停在我这一级（部门主管/副管理员/管理员）的现货出库单。
  def approval_inbox
    base = Current.account.mes_shipments.where(kind: 'STOCK', status: 'PENDING_APPROVAL')
    scope = admin_like? ? base : base.where(manager_id: current_user.id)
    @shipments = scope.includes(:owner, :crm_customer).order(submitted_at: :desc)
    @shipments_count = @shipments.size
    render 'api/v1/accounts/mes/shipments/index'
  end

  private

  def fetch_shipment
    @shipment = Current.account.mes_shipments.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Shipment)
  end

  def admin_like?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  # 能否审核该现货出库单：管理员/副管理员，或本单指定审核人（业务员所属部门主管）本人。
  def can_approve_shipment?(shipment)
    admin_like? || shipment.manager_id == current_user.id
  end

  # 出库单可见范围：现货出库看开单人(owner)可见范围；生产出库看其生产订单归属可见范围。
  # 操作岗/管理员（visible_owner_ids == :all）看全部。
  def scope_visible(scope)
    ids = mes_visible_owner_ids
    return scope if ids == :all

    visible_pos = Current.account.mes_production_orders.where(owner_id: ids).select(:id)
    scope.where(owner_id: ids).or(scope.where(production_order_id: visible_pos))
  end

  def shipment_params
    params.require(:shipment).permit(
      :kind, :crm_sales_order_id, :crm_customer_id, :production_order_id, :warehouse_id, :owner_id, :remark,
      shipment_items_attributes: [:id, :crm_product_id, :qty, :unit, :remark, :_destroy]
    )
  end
end
