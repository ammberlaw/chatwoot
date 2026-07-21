class Api::V1::Accounts::Mes::ProductionOrdersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_production_order,
                only: [:show, :update, :destroy, :attach, :detach, :audits, :attach_bom, :release_purchasing, :requirement, :acknowledge, :reject]

  COLUMN_FILTERS = { stage: :stage, status: :status, crm_sales_order_id: :crm_sales_order_id, owner_id: :owner_id }.freeze

  def index
    scope = scoped_by_product_line(Current.account.mes_production_orders)
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = scope.where('order_no ILIKE :t OR product_name ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @production_orders_count = scope.count
    @production_orders = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @production_order = Current.account.mes_production_orders.new(
      production_order_params.merge(owner_id: production_order_params[:owner_id] || current_user.id)
    )
    @production_order.fallback_product_line = current_product_line
    @production_order.save!
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 从销售订单一键转生产订单（脊柱起点）。成品/数量优先取参数，缺则从销售订单带默认。
  def convert
    sales_order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    product = Current.account.crm_products.find_by(id: params[:crm_product_id])
    @production_order = Current.account.mes_production_orders.new(
      crm_sales_order: sales_order,
      crm_product: product,
      product_name: params[:product_name].presence || product&.name,
      qty: params[:qty],
      unit: params[:unit],
      delivery_date: params[:delivery_date].presence || sales_order.delivery_date,
      owner_id: params[:owner_id] || current_user.id
    )
    @production_order.fallback_product_line = current_product_line
    @production_order.save!
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 按 BOM 推料（生产领料预填）：返回该生产订单的用料需求。
  def requirement
    render json: { payload: @production_order.material_requirements }
  end

  # 挂工程 BOM（阶段 2）：绑 BOM + 预估交期 → 进 BOM_READY。
  def attach_bom
    bom = Current.account.mes_boms.find(params[:bom_id])
    @production_order.attach_bom!(bom, planned_end: params[:planned_end_date])
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 工程/PMC 制单后一键下发到采购阶段（BOM_READY → PURCHASING）。
  def release_purchasing
    @production_order.release_to_purchasing!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 接单：本阶段负责人（或管理员）确认接手。计时不受影响，仅定性。
  def acknowledge
    return render json: { error: '只有本阶段负责人可接单' }, status: :forbidden unless can_handle_stage?(@production_order)

    @production_order.acknowledge!(current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 拒收打回：退回上一阶段并记原因，责任明确回上游。
  def reject
    return render json: { error: '只有本阶段负责人可拒收' }, status: :forbidden unless can_handle_stage?(@production_order)

    reason = params[:reason].to_s.strip
    return render json: { error: '请填写退回原因' }, status: :unprocessable_entity if reason.blank?

    @production_order.reject_to_previous!(actor: current_user, reason: reason)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 我的待办：当前停在「我负责的阶段」的在产订单（到岗通知的拉取面）。
  def inbox
    owners = Current.account.mes_board_owners.index_by(&:board_key)
    open_orders = Current.account.mes_production_orders
                         .where(status: 'IN_PROGRESS').where.not(stage: 'SHIPPED')
                         .includes(:stage_events).order(created_at: :desc)
    mine = open_orders.select do |po|
      key = Mes::ProductionOrder::STAGE_BOARD_KEYS[po.stage]
      key && owners[key]&.manager_ids&.include?(current_user.id)
    end
    render json: { payload: mine.map { |po| inbox_row(po) } }
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

  # 能否处理该阶段：本阶段负责人本人，或管理员/副管理员。
  def can_handle_stage?(order)
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin? ||
      order.current_stage_owner_ids.include?(current_user.id)
  end

  def inbox_row(order)
    {
      id: order.id,
      order_no: order.order_no,
      product_name: order.product_name,
      stage: order.stage,
      awaiting_ack: order.awaiting_ack?,
      ack_overdue: order.ack_overdue?,
      ack_deadline: order.ack_deadline,
      entered_at: order.stage_entered_at
    }
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
