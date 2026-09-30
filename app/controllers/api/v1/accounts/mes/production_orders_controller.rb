class Api::V1::Accounts::Mes::ProductionOrdersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_production_order,
                only: [:show, :update, :destroy, :attach, :detach, :audits, :forward, :attach_bom, :detach_bom, :revert_to_bom_ready, :release_purchasing, :requirement, :handoff,
                       :issue_plan, :acknowledge, :reject, :submit_approval, :approve, :deny, :set_product_code, :mark_outsourced]
  before_action :ensure_editable!, only: [:update, :attach, :detach]
  before_action :ensure_deletable!, only: [:destroy]

  COLUMN_FILTERS = { stage: :stage, status: :status, crm_sales_order_id: :crm_sales_order_id, owner_id: :owner_id }.freeze

  # 列表分片 _mes_production_order 逐行解引用的关联，一次预加载掉。
  LIST_EAGER_LOADS = [
    :owner, :outsource_supplier, :bom, :bom_confirmed_by, :gm, :stage_ack_by,
    :crm_customer, :crm_product, :crm_sales_order, :stage_events, :purchase_orders,
    { images_attachments: :blob, files_attachments: :blob }
  ].freeze

  def index
    scope = scoped_by_owner(scoped_by_product_line(Current.account.mes_production_orders.visible_to(current_user)))
    scope = apply_list_scope(scope)
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = apply_search(scope)
    @production_orders_count = scope.count
    # 列表分片逐行取这些关联，不预加载就是每行一次查库（dev 的 Bullet 直接抛异常打断页面）。
    @production_orders = scope.includes(LIST_EAGER_LOADS).order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  def create
    @production_order = Current.account.mes_production_orders.new(
      production_order_params.merge(owner_id: production_order_params[:owner_id] || current_user.id)
    )
    # 无 :order 能力的业务角色：只能给自己建「按单生产」单（备货/代建仍归 PMC/管理员）。
    unless Current.account_user.mes_can?(:order)
      @production_order.owner_id = current_user.id
      @production_order.order_kind = 'CUSTOMER'
      # 业务员建单：订单编号须从 CRM 销售订单下拉选择关联（带出 PI 号）。
      if @production_order.crm_sales_order_id.blank?
        return render json: { error: '请先关联 CRM 销售订单（订单编号从销售订单下拉选择）' }, status: :unprocessable_entity
      end
    end
    @production_order.fallback_product_line = current_product_line
    @production_order.save!
    # submit=true：建单即提交审批（业务员点「提交审批」）；否则留草稿。
    @production_order.submit_for_approval!(current_user) if boolean_param(:submit)
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 暂存文件为 ActiveStorage blob（建单前即可上传）：返回 signed_id，建单时通过 images/files 挂载。
  def stage_blob
    file = params[:file]
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.open, filename: file.original_filename, content_type: file.content_type
    )
    render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, url: rails_blob_path(blob, only_path: true) }
  end

  # 从销售订单一键转生产订单（脊柱起点）。**每行明细各转一张**——生产脊柱按成品走，
  # 一张生产订单只做一个成品，所以一张多型号的销售订单对应多张生产订单（都挂回同一张销售单）。
  #
  # 幂等按「销售订单 + 产品」判，不是整单判：
  #   连点两下、前后端重试都不会重复建；订单后来补了一行明细，再转一次只会补那一行。
  #   （同一张订单同一个产品拆成两行的情况生产上没有，真出现时按一张单转，数量业务自行合并。）
  #
  # 审批口径按能力分（业务员一键转单不是绕审批的口子）：
  #   有 :order 能力（PMC/管理员）→ 直接 APPROVED 进生产流转；
  #   业务员等 CRM 角色 → 落草稿并提交审批，主管/总经理审完才生效。
  def convert
    sales_order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    rows = convert_rows
    return render json: { error: '请至少选择一行明细' }, status: :unprocessable_entity if rows.empty?

    converted = converted_product_nos(sales_order)
    pending = rows.reject { |row| converted.key?(row[:crm_product_id]) }
    if pending.empty?
      return render json: { error: "所选明细都已生成生产订单（#{converted.values.uniq.join('、')}），不能重复转单" },
                    status: :unprocessable_entity
    end

    orders = ActiveRecord::Base.transaction { pending.map { |row| save_converted_order(sales_order, row) } }
    render json: { order_nos: orders.map(&:order_no), skipped: rows.size - pending.size }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 按 BOM 推料（生产领料预填）：默认只推**整机生产物料**（包装物料未到不挡开产，
  # 打包时再另领）；传 category=PACKAGING 可单推包装料。
  def requirement
    category = params[:category].presence || 'MACHINE'
    rows = @production_order.material_requirements(category: category)
    # 供应商信息只对 MES 人员可见；销售等非 MES 角色隐去 mes_supplier_id（与 jbuilder 同门禁）。
    rows.each { |r| r.delete(:mes_supplier_id) } unless Current.account_user&.mes_staff?
    render json: { payload: rows }
  end

  # 生产领料计划：BOM 推料 + 每行「已领量/实时库存/待领量」。warehouse_id 传入算该仓库存。
  def issue_plan
    rows = @production_order.issue_plan(
      warehouse_id: params[:warehouse_id].presence,
      category: params[:category].presence || 'MACHINE'
    )
    rows.each { |r| r.delete(:mes_supplier_id) } unless Current.account_user&.mes_staff?
    render json: { payload: rows }
  end

  # 挂工程 BOM（阶段 2）：绑 BOM + 期望交期 → 进 BOM_READY。预估完工仍按 BOM 天数自动算。
  def attach_bom
    bom = Current.account.mes_boms.find(params[:bom_id])
    @production_order.update!(delivery_date: params[:delivery_date]) if params[:delivery_date].present?
    @production_order.attach_bom!(bom)
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 工程/PMC 制单后一键下发到采购阶段（BOM_READY → PURCHASING）。
  def release_purchasing
    @production_order.release_to_purchasing!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 解除 BOM 关联（挂错了重挂）：清 bom_id 并退回「待工程接单」。
  def detach_bom
    @production_order.detach_bom!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 采购原料退回工程/PMC BOM（下发早了 / BOM 要改）。
  def revert_to_bom_ready
    @production_order.revert_to_bom_ready!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 工程判定为外购成品：选定产品+供应商，跳过 BOM 直接进采购（短版脊柱）。
  def mark_outsourced
    @production_order.mark_outsourced!(
      crm_product_id: params[:crm_product_id].presence,
      supplier_id: params[:mes_supplier_id].presence,
      product_name: params[:product_name].presence,
      actor: current_user
    )
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

  # 转给同阶段另一位负责人（工程 ↔ PMC 接力）。转出后接单状态清空，
  # 接收人那边重新出现「待我接单」。
  def handoff
    return render json: { error: '只有本阶段负责人可转交' }, status: :forbidden unless can_handle_stage?(@production_order)

    to_user = Current.account.users.find_by(id: params[:to_user_id])
    return render json: { error: '请选择要转交的负责人' }, status: :unprocessable_entity if to_user.blank?

    @production_order.handoff_stage!(actor: current_user, to_user: to_user, note: params[:note])
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
    # 按 (板块, 产品线) 预载负责人；每单按其产品线取，未配专属则回落「全部产线」。
    by_key_line = Current.account.mes_board_owners.to_a
                         .index_by { |o| [o.board_key, o.product_line.to_s] }
    resolve = lambda do |key, line|
      (line.present? && by_key_line[[key, line]]&.manager_ids.presence) ||
        by_key_line[[key, '']]&.manager_ids || []
    end
    open_orders = Current.account.mes_production_orders.published
                         .where(status: 'IN_PROGRESS').where.not(stage: 'SHIPPED')
                         .includes(:stage_events).order(created_at: :desc)
    mine = open_orders.select do |po|
      key = Mes::ProductionOrder::INBOX_BOARD_KEYS[po.stage]
      key && resolve.call(key, po.product_line.to_s).include?(current_user.id)
    end
    render json: { payload: mine.map { |po| inbox_row(po) } }
  end

  # ── 审批链：提交 → 部门主管通过/驳回 → 总经理通过/驳回 ──

  # 提交审批（草稿/被驳回 → 待部门主管）。仅创建人或管理员可提交。
  def submit_approval
    return render json: { error: '只有创建人可提交审批' }, status: :forbidden unless @production_order.owner_id == current_user.id || admin_like?

    @production_order.submit_for_approval!(current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 通过：按当前环节校验审批人（部门主管本人 / 总经理本人 / 管理员）。
  def approve
    return render json: { error: '无权审批当前环节' }, status: :forbidden unless can_approve?(@production_order)

    comment = params[:comment].to_s.strip.presence
    case @production_order.approval_status
    when 'SUBMITTED' then @production_order.manager_approve!(current_user, comment: comment)
    when 'MANAGER_APPROVED' then @production_order.gm_approve!(current_user, comment: comment)
    else return render json: { error: '当前状态无法审批' }, status: :unprocessable_entity
    end
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 驳回：退回业务员（可改后重提）。需填原因。
  def deny
    return render json: { error: '无权审批当前环节' }, status: :forbidden unless can_approve?(@production_order)

    reason = params[:reason].to_s.strip
    return render json: { error: '请填写驳回原因' }, status: :unprocessable_entity if reason.blank?

    @production_order.reject_approval!(current_user, reason: reason)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 待我确认：停在我这一级的审批单（部门主管/总经理）+ 待我二次确认 BOM 的单（业务员）。
  def approval_inbox
    base = Current.account.mes_production_orders
    scope = base.awaiting_manager_for(current_user.id)
                .or(base.awaiting_gm_for(current_user.id))

    @production_orders = scope.includes(:owner).order(submitted_at: :desc)
    @production_orders_count = @production_orders.size
    render 'api/v1/accounts/mes/production_orders/index'
  end

  # 产品编码：由工程/PMC 编写（唯一，供 ERP 共享）。策略 set_product_code? 限 bom 能力。
  def set_product_code
    @production_order.update!(product_code: params[:product_code].to_s.strip.presence)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors[:product_code].first || e.message }, status: :unprocessable_entity
  end

  def update
    # 已下发（非草稿）订单被改 → 改完通知当前阶段的下一个流程负责人（需求：改单同步下游）。
    was_published = !@production_order.is_draft
    @production_order.update!(production_order_params)
    @production_order.notify_order_revised(actor: current_user) if was_published
    render 'api/v1/accounts/mes/production_orders/show'
  end

  def destroy
    @production_order.destroy!
    head :ok
  end

  # kind = images（产品图片）| files（附件），默认 files。
  ATTACH_COLLECTIONS = { 'images' => :images, 'files' => :files }.freeze

  def attach
    @production_order.public_send(attach_collection).attach(params[:files])
    render 'api/v1/accounts/mes/production_orders/show'
  end

  def detach
    @production_order.public_send(attach_collection).find(params[:attachment_id]).purge
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 业务转发：把订单知会给某阶段负责人（选板块）+ 附言，推站内通知并在订单上留痕。
  def forward
    @production_order.forward_to_board!(
      sender: current_user, board_key: params[:board_key], note: params[:note]
    )
    render 'api/v1/accounts/mes/production_orders/show'
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  # 转单落库字段：成品/数量/单位优先取转单弹窗传来的（明细在那儿逐行确认过），缺则从销售订单带。
  # 转单明细：新版前端传 items 数组（每行一个成品）。
  # 旧版单行参数（crm_product_id/qty/unit）继续认，避免老页面缓存着就转不了单。
  def convert_rows
    raw = params[:items].presence || [params.permit(:crm_product_id, :qty, :unit, :product_name, :delivery_date, :owner_id)]
    Array(raw).filter_map do |item|
      row = item.respond_to?(:permit) ? item.permit(:crm_product_id, :qty, :unit, :product_name, :delivery_date, :owner_id) : item
      product_id = row[:crm_product_id].presence&.to_i
      next if product_id.blank? || row[:qty].to_d <= 0

      { crm_product_id: product_id, qty: row[:qty], unit: row[:unit].presence,
        product_name: row[:product_name].presence, delivery_date: row[:delivery_date].presence,
        owner_id: row[:owner_id].presence }
    end
  end

  # 该销售订单下已转过的 产品id → 生产订单号（已取消的不算，取消后可以重转）。
  def converted_product_nos(sales_order)
    Current.account.mes_production_orders
           .where(crm_sales_order_id: sales_order.id).where.not(status: 'CANCELLED')
           .pluck(:crm_product_id, :order_no).to_h
  end

  def save_converted_order(sales_order, row)
    order = build_converted_order(sales_order, row)
    order.fallback_product_line = current_product_line
    order.save!
    order.submit_for_approval!(current_user) unless Current.account_user.mes_can?(:order)
    order
  end

  def build_converted_order(sales_order, row)
    product = Current.account.crm_products.find_by(id: row[:crm_product_id])
    Current.account.mes_production_orders.new(
      converted_order_attrs(sales_order, product, row).merge(
        crm_sales_order: sales_order, crm_product: product, order_kind: 'CUSTOMER',
        # 有 :order 能力者由已确认销售订单转入，直接生效；业务员转入的落草稿等审批（见 convert）。
        approval_status: Current.account_user.mes_can?(:order) ? 'APPROVED' : 'DRAFT'
      )
    )
  end

  def converted_order_attrs(sales_order, product, row)
    {
      crm_customer_id: sales_order.crm_customer_id,
      product_name: row[:product_name] || product&.name,
      qty: row[:qty],
      unit: row[:unit],
      pi_no: sales_order.pi_no,
      delivery_date: row[:delivery_date] || sales_order.delivery_date,
      owner_id: row[:owner_id] || sales_order.owner_id || current_user.id
    }
  end

  # 每页条数：默认沿用 RESULTS_PER_PAGE(15)，供列表分页；调用方(如报工订单下拉)需一次性
  # 拿到全部在产订单时可传 per_page，封顶 500 防止拉全表。
  MAX_PER_PAGE = 500
  def per_page_param
    n = params[:per_page].to_i
    n = RESULTS_PER_PAGE if n <= 0
    [n, MAX_PER_PAGE].min
  end

  # 列表分档：mine=我的客户订单（归属我）｜ stock=库存备货（全业务共享）｜ all=可见全部。
  def apply_list_scope(scope)
    case params[:list_scope]
    when 'mine' then scope.where(owner_id: current_user.id, order_kind: 'CUSTOMER')
    when 'stock' then scope.stock
    else scope
    end
  end

  # 关键词搜索：工单号 / 成品名 / 产品料号。
  # 搜工单号 / 成品名 / 商品编码（= 关联产品档案 sku）。
  def apply_search(scope)
    return scope if params[:q].blank?

    scope.left_joins(:crm_product).where(
      'mes_production_orders.order_no ILIKE :t OR mes_production_orders.product_name ILIKE :t OR crm_products.sku ILIKE :t',
      t: "%#{params[:q].strip}%"
    )
  end

  def fetch_production_order
    @production_order = Current.account.mes_production_orders.find(params[:id])
  end

  def attach_collection
    ATTACH_COLLECTIONS[params[:kind]] || :files
  end

  # 能否处理该阶段：本阶段负责人本人，或管理员/副管理员。
  def can_handle_stage?(order)
    admin_like? || order.current_stage_owner_ids.include?(current_user.id)
  end

  def admin_like?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  # 能否审批当前环节：管理员，或本环节指定审批人本人。
  def can_approve?(order)
    return false unless order.pending_approval?
    return true if admin_like?

    order.current_approver_id == current_user.id
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
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

  # 编辑权：PMC/管理员不受限；归属业务可改**本人订单（含已下发）**——已下发的改动
  # 由 update 通知下游负责人。无 order 能力且非本人订单则拒。
  def ensure_editable!
    ensure_owner_or_admin!(@production_order, '生产订单')
  end

  # 删除权：管理员删任意；其余仅能删**本人的草稿**（已下发进入生产流程不可删）。
  def ensure_deletable!
    return if admin_like?
    return if @production_order.is_draft && @production_order.owner_id == current_user.id

    render json: { error: '仅本人草稿可删除；已下发订单不可删除' }, status: :forbidden
  end

  def production_order_params
    permitted = params.require(:production_order).permit(
      :crm_sales_order_id, :crm_customer_id, :crm_product_id, :product_name, :qty, :unit, :pi_no,
      :bom_id, :order_kind, :delivery_date, :planned_start_date, :planned_end_date,
      :actual_start_date, :actual_end_date, :owner_id, :remark, :product_line,
      images: [], files: [] # 建单时挂载已暂存的 blob signed_id
    )
    # stage/status/produced_qty 由状态机（接单/领料/报工/出库过账）驱动，销售端不得直接改单越过流程；
    # 仅持生产订单管理能力(:order)者可手工干预。
    if Current.account_user&.mes_can?(:order)
      permitted.merge!(params.require(:production_order).permit(:stage, :status, :produced_qty).to_h)
    end
    # spec 为按产品线的定制规格 jsonb（字段动态），整体透传。
    raw_spec = params.require(:production_order)[:spec]
    permitted[:spec] = raw_spec.respond_to?(:permit!) ? raw_spec.permit!.to_h : raw_spec if raw_spec.present?
    permitted
  end
end
