# 出库单：转单/建单/审核/通知/出库/删单聚合在一个控制器，方法多但内聚，故豁免 ClassLength。
# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Mes::ShipmentsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_shipment,
                only: [:show, :update, :destroy, :notify, :ship, :submit, :approve, :reject, :revert_to_draft, :void,
                       :diagnose]
  before_action -> { ensure_owner_or_admin!(@shipment, '出库单') }, only: [:update]
  before_action :ensure_can_delete!, only: [:destroy]

  COLUMN_FILTERS = { status: :status, kind: :kind, crm_sales_order_id: :crm_sales_order_id }.freeze
  # 重复开单提示里用的状态中文（只给人看，不做业务判断）。
  DUP_STATUS_LABELS = { 'DRAFT' => '草稿', 'PENDING_APPROVAL' => '待审核', 'APPROVED' => '已审核', 'REJECTED' => '已驳回', 'SHIPPED' => '已出库' }.freeze

  def index
    scope = scope_by_product_line_or_stock(Current.account.mes_shipments)
    COLUMN_FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = scope_visible(search_scope(scope))
    @shipments_count = scope.count
    # 列表视图逐行要取客户 / 发货仓 / 制单人 / 销售订单（含业务员和订单明细行），
    # 不预加载就是每行七八条查询。
    @shipments = scope.includes(:crm_customer, :warehouse, :owner, :manager, { production_order: :owner },
                                { crm_sales_order: [:owner, :crm_customer] }, { shipment_items: :crm_product })
                      .order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
    # with_receivable=1：财务的「出库审核」清单要在列表上直接看到「款收齐没有」，
    # 否则得逐张点开。只在这个场景开，普通列表不算——逐行跑回款进度是 N+1。
    @with_receivable = params[:with_receivable].present?
  end

  # 待我审核的出库单数量（ERP 侧栏角标用）。财务不进 MES 也该知道有几张等着批。
  def pending_count
    # 小额单（仓库自己批那些）不计进财务的角标，否则角标永远清不掉——财务不该再去看它们。
    # 逐条判定是 Ruby 侧的事，但待审单常年个位数，不值得为它拼一段 join 销售订单的 SQL。
    count = if Mes::Shipment.approver?(Current.account, Current.account_user)
              scope_visible(Current.account.mes_shipments)
                .where(status: 'PENDING_APPROVAL').includes(:crm_sales_order)
                .count { |shipment| !shipment.warehouse_self_approvable? }
            else
              0
            end
    render json: { count: count }
  end

  def show; end

  # 打印后记一次。仓库每月要把整叠单打出来给财务核对，列表上得能分出哪些打过了。
  # 不记谁打的、不记时间——仓库要的就是一个「打过没打过」的计数（2026-10-21）。
  def mark_printed
    ids = Array(params[:ids]).map(&:to_i).select(&:positive?)
    return render json: { payload: [] } if ids.empty?

    scope = scope_visible(Current.account.mes_shipments).where(id: ids)
    scope.update_all('print_count = print_count + 1') # rubocop:disable Rails/SkipsModelValidations
    render json: { payload: scope.pluck(:id, :print_count).map { |id, count| { id: id, print_count: count } } }
  end

  # 从销售订单一键转现货出库单（库存单轨道的起点）。
  # 明细由前端带来（销售订单明细是自由文本，产品档案在转单弹窗里逐行确认过），
  # 这里只认 crm_product_id + 数量，认不出产品的行前端不会放过来。
  # 幂等：同一销售订单已有未取消的出库单就拦下，不重复生成（业务员连点两下很常见）。
  def convert
    sales_order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    return unless convertible?(sales_order)

    # 建单与提交必须同生共死：原先没包事务，现货不足导致 submit 失败时出库单已落库，
    # 之后这张销售订单永远报「已生成出库单 DN-xxx，不能重复转单」——转不动也看不出
    # 该去删那张草稿。回滚掉就当这次转单没发生过。
    @shipments = ActiveRecord::Base.transaction do
      items_by_warehouse.map { |warehouse_id, items| build_converted_shipment!(sales_order, warehouse_id, items) }
    end
    @shipment = @shipments.first
    record_tax_basis!(sales_order)
    # 人工点中的产品落回明细 + 别名记忆，下次不用再从上千条产品档案里搜一遍。
    Crm::ConvertChoiceRecorder.new(sales_order).call(convert_choice_rows)
    render json: { shipment_nos: @shipments.map(&:shipment_no), count: @shipments.size,
                   shipment_no: @shipment&.shipment_no }
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 现货出库单由 CRM 业务条线开单（无出库能力者一律记为 STOCK，开单即进入审核）。
  def create
    dup_error = duplicate_order_error
    return render json: { error: dup_error }, status: :unprocessable_entity if dup_error

    @shipment = build_shipment
    @shipment.fallback_product_line = current_product_line
    resolve_missing_product_ids(@shipment)
    @shipment.save!
    # 两种出库都提交财务审核（过账都会打 ERP）。原先只有现货走，生产出库建完就能直接出。
    @shipment.submit_for_approval!(current_user)
    render 'api/v1/accounts/mes/shipments/show'
  rescue Pundit::NotAuthorizedError
    raise # 权限不足要回 403，别被下面的 422 吞掉
  rescue StandardError => e
    # 同成品入库：这里抛的多是业务校验（如「订单没关联产品档案」），
    # 不 rescue 的话用户只看到黑框 Internal Server Error，看不到原因。
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  def update
    @shipment.assign_attributes(shipment_params)
    resolve_missing_product_ids(@shipment)
    @shipment.save!
    render 'api/v1/accounts/mes/shipments/show'
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
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

  # 退回草稿：做错了就地改，不用删了重建。
  def revert_to_draft
    return render json: { error: '无权退回该出库单' }, status: :forbidden unless can_revert?(@shipment)

    @shipment.revert_to_draft!(current_user)
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 作废：整张单不要了，置「已作废」留痕，销售订单可以重新转单。
  def void
    return render json: { error: '无权作废该出库单' }, status: :forbidden unless can_revert?(@shipment)

    @shipment.void!(current_user, reason: params[:reason])
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
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
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 主管审核通过 → 推仓库。
  def approve
    return render json: { error: '无权审核该出库单' }, status: :forbidden unless can_approve_shipment?(@shipment)

    # 款没收齐时财务仍可放行，但要带理由（模型里校验），留痕。
    @shipment.approve!(current_user, note: params[:note])
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 主管驳回 → 退回业务员（需填原因）。
  def reject
    return render json: { error: '无权审核该出库单' }, status: :forbidden unless can_approve_shipment?(@shipment)

    reason = params[:reason].to_s.strip
    return render json: { error: '请填写驳回原因' }, status: :unprocessable_entity if reason.blank?

    @shipment.reject!(current_user, reason: reason)
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 出库：扣成品库存 + 回写销售订单已出货。
  def ship
    @shipment.ship!
    render 'api/v1/accounts/mes/shipments/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 「我为什么干不了这件事」——只读自助诊断（见 Mes::ShipmentDiagnosis）。
  # 不只解释报错：按钮不见、提交完没动静，挡住人的是同一套判定，这里一并答。
  def diagnose
    render json: { payload: Mes::ShipmentDiagnosis.new(
      shipment: @shipment, account_user: Current.account_user
    ).call(params[:do_action]) }
  end

  # 待我审核：停在我这一级（部门主管/副管理员/管理员）的现货出库单。
  # 待我审核的出库单。判定走统一出口，不在这儿另写一条 where。
  #
  # 原先是 `where(kind: 'STOCK').where(manager_id: current_user.id)`，两处都错：
  # manager_id 在 submit_for_approval! 里被置成 nil（提交时还不知道该谁审），
  # 按它过滤等于永远查不到；kind 又把生产出库整类漏掉。
  # 于是「待我处理」面板少显示出库单，侧栏角标（走 Mes::TodoList）却算得出来，
  # 两边对不上（2026-10-26：角标 5、面板 4，差的就是这一条）。
  def approval_inbox
    rows = Mes::TodoList.new(account: Current.account, account_user: Current.account_user)
                        .shipment_approvals
    @shipments = rows.sort_by { |s| s.submitted_at || s.created_at }.reverse
    @shipments_count = @shipments.size
    render 'api/v1/accounts/mes/shipments/index'
  end

  private

  # 没有出库能力的人（业务员开现货单）一律落 STOCK，走主管审核流。
  def build_shipment
    attrs = shipment_params
    stock = attrs[:kind] == 'STOCK' || !Current.account_user.mes_can?(:shipment)
    Current.account.mes_shipments.new(
      attrs.merge(owner_id: attrs[:owner_id] || current_user.id, kind: stock ? 'STOCK' : 'PRODUCTION')
    )
  end

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
  # 退回/作废的门槛同删单：仓管能做，开单人自己也能做（做错的多半是自己）。
  def can_revert?(shipment)
    Current.account_user.mes_can?(:shipment) || shipment.owner_id == current_user.id || admin_like?
  end

  def ensure_can_delete!
    return if Current.account_user.mes_can?(:shipment)

    ensure_owner_or_admin!(@shipment, '出库单')
  end

  # 生产出库单若明细缺商品编码（建单时成品名选填导致），按订单成品名兜底建/关联编码，
  # 保证成品库存按 SKU 扣减、不串库。现货出库(STOCK)明细来自产品档案本就带编码，不受影响。
  # 转单时勾的「订单金额已含税」写回销售订单——出库后的收入凭证按它拆行。
  # 放在转单而不是建单：业务员建单时未必想得起来，转单的人是要对金额负责的那个。
  #
  # 订单类型一并写回（2026-10-22）：以前转单选的类型只管这一次，订单上那栏照旧空着，
  # 下次转同一张单还得再选一遍。既然转单的人已经判断过这单该走哪条线，就以他选的为准。
  def record_tax_basis!(sales_order)
    tax = params[:amount_includes_tax]
    attrs = { order_kind: 'STOCK', updated_at: Time.current }
    attrs[:amount_includes_tax] = ActiveModel::Type::Boolean.new.cast(tax) unless tax.nil?
    sales_order.update_columns(attrs) # rubocop:disable Rails/SkipsModelValidations
  end

  # 转单前的两道闸：销售订单审过没有、这张单是不是已经转过了。
  # 审核闸同转生产订单那条路；库存单这条更要卡——转单即预占库存、批完货就走了，
  # 中间没有开料采购那些缓冲环节。
  def convertible?(sales_order)
    unless sales_order.pushable?
      render json: { error: "销售订单 #{sales_order.order_no} #{sales_order.approval_label}，审核通过后才能转出库单" },
             status: :unprocessable_entity
      return false
    end

    existing = converted_shipment_for(sales_order)
    return true if existing.nil?

    render json: { error: "该订单已生成出库单 #{existing.shipment_no}，不能重复转单" }, status: :unprocessable_entity
    false
  end

  def converted_shipment_for(sales_order)
    Current.account.mes_shipments.where(crm_sales_order_id: sales_order.id).where.not(status: 'CANCELLED').first
  end

  # 一个仓一张出库单。
  #
  # 外贸现货单常常一张单里既有成品（外贸仓）又有配件（原材料仓），而出库单的仓库在**单头**、
  # 明细行没有仓库字段：预占量、扣库存、仓管审批路由全按单头那个仓走（见 Mes::Shipment#reserved）。
  # 所以不是给行加仓库，而是按行上选的仓分组、各出一张——每张仍然只有一个仓，
  # 库存那套逻辑一行不用改，而且本来就是两个仓库各自的作业，各仓的仓管各管各的那张更清楚。
  def items_by_warehouse
    rows = convert_items
    grouped = rows.group_by { |row| row[:warehouse_id].presence || params[:warehouse_id] }
    raise StandardError, '请为每一行选择出库仓库' if grouped.keys.any?(&:blank?)

    grouped
  end

  def build_converted_shipment!(sales_order, warehouse_id, items)
    shipment = Current.account.mes_shipments.new(
      converted_shipment_attrs(sales_order, warehouse_id, items)
    )
    shipment.fallback_product_line = current_product_line
    shipment.save!
    # 与手工开单同路径：提交即预占成品库存并进主管审核。
    shipment.submit_for_approval!(current_user)
    shipment
  end

  def converted_shipment_attrs(sales_order, warehouse_id, items)
    {
      kind: 'STOCK',
      crm_sales_order: sales_order,
      crm_customer_id: sales_order.crm_customer_id,
      warehouse_id: warehouse_id,
      owner_id: sales_order.owner_id || current_user.id,
      remark: converted_remark(sales_order),
      shipment_items_attributes: items.map { |row| row.except(:warehouse_id) }
    }
  end

  # 出库单备注 = 转入出处 + 业务在转单弹窗里写的那段。
  # 出处那行不能被覆盖掉——出库单翻回头要能看出是哪张销售订单转来的。
  def converted_remark(sales_order)
    ["由销售订单 #{sales_order.order_no} 转入", params[:remark].presence].compact.join("\n")
  end

  def convert_items
    all_rows = Array(params[:items]).map do |row|
      row.permit(:crm_product_id, :qty, :unit, :remark, :warehouse_id, :color)
    end
    rows = all_rows.select { |r| r[:crm_product_id].present? && r[:qty].to_d.positive? }
    raise StandardError, '没有可转的明细行（每行都要选中产品档案并填数量）' if rows.empty?

    # ⚠️ 缺产品/缺数量的行**不能静默跳过**。原来是 filter_map 直接 next 掉：
    # 只要有一行匹配上，转单就"成功"，剩下的行连人带货一起消失，没有任何提示——
    # 货少发了谁都不知道。界面上 canSubmit 已经拦了，但这里是 API，App 和别的
    # 调用方绕得过去，后端必须自己把门守住。
    skipped = all_rows.size - rows.size
    raise StandardError, "有 #{skipped} 行没选产品档案或没填数量，转单已取消；补齐后再转，以免少发货" if skipped.positive?

    rows.map { |r| r.to_h.symbolize_keys }
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

  # 列表关键字：出库单号 / 销售订单号 / 客户名 / 信保订单号 / 产品名。
  # 一个月几十张单，原先这页既没有搜索也没有状态筛选，只能靠翻页找。
  SEARCH_SQL = <<~SQL.squish
    mes_shipments.shipment_no ILIKE :kw
    OR so.order_no ILIKE :kw
    OR so.insurance_order_no ILIKE :kw
    OR COALESCE(c.name, soc.name) ILIKE :kw
    OR EXISTS (
      SELECT 1 FROM mes_shipment_items si
      JOIN crm_products p ON p.id = si.crm_product_id
      WHERE si.shipment_id = mes_shipments.id AND (p.name ILIKE :kw OR p.sku ILIKE :kw)
    )
  SQL

  def search_scope(scope)
    keyword = params[:q].to_s.strip
    return scope if keyword.blank?

    scope.joins('LEFT JOIN crm_sales_orders so ON so.id = mes_shipments.crm_sales_order_id')
         .joins('LEFT JOIN crm_customers c ON c.id = mes_shipments.crm_customer_id')
         .joins('LEFT JOIN crm_customers soc ON soc.id = so.crm_customer_id')
         .where(SEARCH_SQL, kw: "%#{keyword}%")
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
  # 审核人是「财务这组人」，不再是提交时解析出的某一个主管——所以不比 manager_id。
  def can_approve_shipment?(shipment)
    shipment.approver_for?(Current.account_user)
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
      shipment_items_attributes: [:id, :crm_product_id, :qty, :unit, :remark, :color, :_destroy]
    )
  end
end
# rubocop:enable Metrics/ClassLength
