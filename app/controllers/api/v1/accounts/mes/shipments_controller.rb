# 出库单：转单/建单/审核/通知/出库/删单聚合在一个控制器，方法多但内聚，故豁免 ClassLength。
# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Mes::ShipmentsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_shipment, only: [:show, :update, :destroy, :notify, :ship, :submit, :approve, :reject]
  before_action -> { ensure_owner_or_admin!(@shipment, '出库单') }, only: [:update]
  before_action :ensure_can_delete!, only: [:destroy]

  COLUMN_FILTERS = { status: :status, kind: :kind, crm_sales_order_id: :crm_sales_order_id }.freeze
  # 重复开单提示里用的状态中文（只给人看，不做业务判断）。
  DUP_STATUS_LABELS = { 'DRAFT' => '草稿', 'PENDING_APPROVAL' => '待审核', 'APPROVED' => '已审核', 'REJECTED' => '已驳回', 'SHIPPED' => '已出库' }.freeze

  def index
    scope = scope_by_product_line_or_stock(Current.account.mes_shipments)
    COLUMN_FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = scope_visible(scope)
    @shipments_count = scope.count
    @shipments = scope.order(created_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  # 从销售订单一键转现货出库单（库存单轨道的起点）。
  # 明细由前端带来（销售订单明细是自由文本，产品档案在转单弹窗里逐行确认过），
  # 这里只认 crm_product_id + 数量，认不出产品的行前端不会放过来。
  # 幂等：同一销售订单已有未取消的出库单就拦下，不重复生成（业务员连点两下很常见）。
  def convert
    sales_order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    if (existing = converted_shipment_for(sales_order))
      return render json: { error: "该订单已生成出库单 #{existing.shipment_no}，不能重复转单" }, status: :unprocessable_entity
    end

    # 建单与提交必须同生共死：原先没包事务，现货不足导致 submit 失败时出库单已落库，
    # 之后这张销售订单永远报「已生成出库单 DN-xxx，不能重复转单」——转不动也看不出
    # 该去删那张草稿。回滚掉就当这次转单没发生过。
    ActiveRecord::Base.transaction do
      @shipment = Current.account.mes_shipments.new(converted_shipment_attrs(sales_order))
      @shipment.fallback_product_line = current_product_line
      @shipment.save!
      # 与手工开单同路径：提交即预占成品库存并进主管审核。
      @shipment.submit_for_approval!(current_user)
    end
    record_tax_basis!(sales_order)
    # 人工点中的产品落回明细 + 别名记忆，下次不用再从上千条产品档案里搜一遍。
    Crm::ConvertChoiceRecorder.new(sales_order).call(convert_choice_rows)
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 现货出库单由 CRM 业务条线开单（无出库能力者一律记为 STOCK，开单即进入审核）。
  def create
    dup_error = duplicate_order_error
    return render json: { error: dup_error }, status: :unprocessable_entity if dup_error

    attrs = shipment_params
    stock = attrs[:kind] == 'STOCK' || !Current.account_user.mes_can?(:shipment)
    @shipment = Current.account.mes_shipments.new(
      attrs.merge(owner_id: attrs[:owner_id] || current_user.id, kind: stock ? 'STOCK' : 'PRODUCTION')
    )
    @shipment.fallback_product_line = current_product_line
    resolve_missing_product_ids(@shipment)
    @shipment.save!
    @shipment.submit_for_approval!(current_user) if @shipment.stock?
    render 'api/v1/accounts/mes/shipments/show'
  end

  def update
    @shipment.assign_attributes(shipment_params)
    resolve_missing_product_ids(@shipment)
    @shipment.save!
    render 'api/v1/accounts/mes/shipments/show'
  end

  def destroy
    # 已出库单据不能删（要撤须走库存冲销）；已审核/待审核单占着成品预占——只允许删草稿/被驳回单。
    unless %w[DRAFT REJECTED].include?(@shipment.status)
      return render json: { error: '仅草稿或被驳回的出库单可删除；已审核/已出库单请走驳回或冲销' },
                    status: :unprocessable_entity
    end
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

  # 同一张生产订单重复开出库单的防线。从销售订单转单那条路早就有幂等拦截
  # （converted_shipment_for），手工「新建生产出库」一直没有——生产上
  # SO-20260916-06 两张草稿、SO-20260901-04 两张已出库，都是这么来的。
  def duplicate_order_error
    order_id = shipment_params[:production_order_id].presence
    return nil if order_id.blank?

    dup = Current.account.mes_shipments.where(production_order_id: order_id).where.not(status: 'CANCELLED').first
    return nil if dup.nil?

    "该生产订单已有出库单 #{dup.shipment_no}（#{DUP_STATUS_LABELS[dup.status] || dup.status}），" \
      '不要重复开单；确需再开请先删掉那张草稿'
  end

  # 删草稿不止制单人：重复草稿多半是仓管在准备出库时才发现的，只许制单人或管理员删，
  # 那张单就会一直挂着（生产上 SO-20260916-06 挂了两张草稿、谁都删不掉）。
  # 仓管（shipment 能力）可以删——destroy 本身已经把范围限死在草稿/被驳回单。
  def ensure_can_delete!
    return if Current.account_user.mes_can?(:shipment)

    ensure_owner_or_admin!(@shipment, '出库单')
  end

  # 生产出库单若明细缺商品编码（建单时成品名选填导致），按订单成品名兜底建/关联编码，
  # 保证成品库存按 SKU 扣减、不串库。现货出库(STOCK)明细来自产品档案本就带编码，不受影响。
  # 转单时勾的「订单金额已含税」写回销售订单——出库后的收入凭证按它拆行。
  # 放在转单而不是建单：业务员建单时未必想得起来，转单的人是要对金额负责的那个。
  def record_tax_basis!(sales_order)
    return if params[:amount_includes_tax].nil?

    sales_order.update_columns(amount_includes_tax: ActiveModel::Type::Boolean.new.cast(params[:amount_includes_tax]),
                               updated_at: Time.current)
  end

  def converted_shipment_for(sales_order)
    Current.account.mes_shipments.where(crm_sales_order_id: sales_order.id).where.not(status: 'CANCELLED').first
  end

  def converted_shipment_attrs(sales_order)
    {
      kind: 'STOCK',
      crm_sales_order: sales_order,
      crm_customer_id: sales_order.crm_customer_id,
      warehouse_id: params[:warehouse_id],
      owner_id: sales_order.owner_id || current_user.id,
      remark: "由销售订单 #{sales_order.order_no} 转入",
      shipment_items_attributes: convert_items
    }
  end

  def convert_items
    rows = Array(params[:items]).filter_map do |row|
      permitted = row.permit(:crm_product_id, :qty, :unit, :remark)
      next if permitted[:crm_product_id].blank? || permitted[:qty].to_d <= 0

      permitted.to_h
    end
    raise StandardError, '没有可转的明细行（每行都要选中产品档案并填数量）' if rows.empty?

    rows
  end

  # 产品关联回写用的 (明细行号 → 产品)。row 是明细行号（1 起），弹窗里手工加的行没有。
  def convert_choice_rows
    Array(params[:items]).map do |row|
      permitted = row.permit(:crm_product_id, :row)
      { crm_product_id: permitted[:crm_product_id], row: permitted[:row] }
    end
  end

  def resolve_missing_product_ids(shipment)
    order = shipment.production_order
    return if order.nil?

    items = shipment.shipment_items.select { |i| i.crm_product_id.blank? }
    return if items.empty?

    pid = order.link_crm_product_by_name!
    # 关联不上就当场拦下，不再按成品名自动建档案——自动建出来的 SKU 是中文品名，
    # 和采购入库用的真编码在结存表里是两个桶，后面怎么查都对不上。
    if pid.blank?
      raise StandardError, "生产订单 #{order.order_no} 没有关联产品档案（成品「#{order.product_name}」在档案里找不到同名项），" \
                           '请先到生产订单上选好成品编码再开出库单'
    end

    items.each { |i| i.crm_product_id = pid }
  end

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
# rubocop:enable Metrics/ClassLength
