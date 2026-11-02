class Api::V1::Accounts::Mes::PurchaseOrdersController < Api::V1::Accounts::Mes::BaseController
  include Api::V1::Accounts::Mes::DocumentReturnable

  before_action :check_authorization
  before_action :fetch_purchase_order,
                only: [:show, :update, :destroy, :export, :export_data, :mark_exported, :submit, :approve, :reject, :close, :reopen]
  # 谁制单谁改（管理员可代改）——采购单的 owner 就是下单人。
  before_action -> { ensure_owner_or_admin!(@purchase_order, '采购单') }, only: [:update, :destroy, :close, :reopen]
  before_action :ensure_approved_before_export!, only: [:export, :export_data, :mark_exported]
  # 审批人按产品线分（平板一位、商显一位），所以「能批」要逐单核对本单 gm_id，
  # 不能只看「他是某条线的审批人」——否则平板的审批人能去批商显的单。
  before_action :ensure_po_approver!, only: [:approve, :reject]

  # 列筛选。owner_id = 下单人（建单的采购员），跟列表里「归属人」（生产订单的业务员）
  # 不是一回事——采购员要的是「只看我下的单」。
  # approval_status 与 status 互相独立（已下单 ≠ 已审批），两个都要能单独筛：
  # 64 张单摆一页，找「还没下单的」或「卡在审批的」只能靠眼睛扫。
  COLUMN_FILTERS = { status: :status, approval_status: :approval_status,
                     production_order_id: :production_order_id, owner_id: :owner_id }.freeze

  def index
    scope = index_scope
    @purchase_orders_count = scope.count
    # 预加载上游单据：序列化要取生产订单的备注和它挂的 BOM 备注（见 _mes_purchase_order.json.jbuilder），
    # 不预加载就是一页 15 条多查 30 次。
    @purchase_orders = scope.includes(production_order: :bom)
                            .order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
    # 入库状态/入库时间要查原料入库单，一页 15 张单逐张查就是 15 次。一次批量取完。
    @inbound_map = Mes::PurchaseInboundStatus.new(Current.account).for_ids(@purchase_orders.map(&:id))
  end

  def show; end

  # 明细行附图：先把图传上来拿 signed_id，随 purchase_items_attributes 一起提交（见 permit）。
  def stage_blob
    file = params[:file]
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.open, filename: file.original_filename, content_type: file.content_type
    )
    render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, url: rails_blob_path(blob, only_path: true) }
  end

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
    return render json: { error: '只有未提交审批的草稿、或已关闭且没到过货的单可以删除' }, status: :unprocessable_entity unless @purchase_order.deletable?

    @purchase_order.destroy!
    head :ok
  end

  # 关闭：这单先不采购了（回冲在途、从审批队列撤下来）。启用：关闭过的单接着用。
  def close = render_after { @purchase_order.close! }
  def reopen = render_after { @purchase_order.reopen! }

  # 提交审批（草稿/被驳回可提交）；审批人按本单产品线解析。
  def submit = render_after { @purchase_order.submit_for_approval!(current_user) }
  # 审批通过 → 生效，累加在途库存。驳回 → 退回制单人。
  def approve = render_after { @purchase_order.gm_approve!(current_user, comment: params[:comment]) }
  def reject = render_after { @purchase_order.reject_approval!(current_user, reason: params[:reason]) }

  # 待我审批的采购单（审批人待办箱）。
  def approval_inbox
    scope = Current.account.mes_purchase_orders.awaiting_gm_for(current_user.id)
    @purchase_orders_count = scope.count
    @purchase_orders = scope.order(submitted_at: :asc, id: :asc).page(page_param).per(per_page_param)
    render 'api/v1/accounts/mes/purchase_orders/index'
  end

  # BOM 算料：按生产订单的 BOM 展开采购需求，供采购单预填。
  def requirement
    production_order = Current.account.mes_production_orders.find(params[:production_order_id])
    # category 可选：MACHINE 主料(整机料) / PACKAGING 辅料(包装料)——支持两个采购员分料建单。
    cat = params[:category].presence
    # blocked：工程/业务还没确认、这轮不下单的料。不带进明细，但要告诉采购有几项、
    # 卡在谁那里——少了几行而没有提示，采购会以为料就这些。
    render json: { payload: production_order.material_requirements(category: cat),
                   blocked: production_order.blocked_requirement_rows(category: cat) }
  end

  # 按供应商拆单导出 PDF：各供应商的料各成一份、填公司原始模板（含公章）→ Gotenberg 转 1:1 PDF，
  # 多家合成**一个** PDF（每家一页）。抬头/税口径按各供应商 bill_entity 自动选
  #（联迪=对公含税带公章 / 联合触控=对私未税）。
  # supplier_ids 可选：只导这几家（预览里勾选用），0 表示「未指定供应商」那组。
  # bill_entities 可选：{ supplier_id => 'wintouch'|'liontek' }，临时改某家抬头，不动供应商档案。
  def export
    exporter = Mes::PoSupplierExport.new(@purchase_order, supplier_ids: params[:supplier_ids],
                                                          bill_entities: bill_entities_param)
    doc = exporter.to_pdf_download
    send_data doc[:io].read, filename: doc[:filename], type: doc[:content_type]
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Mes::GotenbergClient::ConversionError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  # 导出计次：预览里勾选一变就会重拉一次 PDF，所以不在 export 里记，
  # 由前端在真正「下载/导出」那一下调这里，列表的次数才等于「传出去过几次」。
  def mark_exported
    @purchase_order.record_export!
    render 'api/v1/accounts/mes/purchase_orders/show'
  end

  # 这颗料上次下单多少钱、给了哪家。只认审批通过的采购单——没过审的价还可能被老板
  # 打回来改，拿它当参考会把错价一路传下去。
  # 没传供应商＝新建时刚输完料号，连供应商一起带出来；传了就只认这家的价。
  def last_price
    hit = Mes::LastPurchasePrice.for(account: Current.account, supplier_id: params[:mes_supplier_id].presence,
                                     crm_product_id: params[:crm_product_id].presence,
                                     mes_material_id: params[:mes_material_id].presence,
                                     # 编辑态把本单排除掉，否则比的是自己（见 Mes::LastPurchasePrice）
                                     exclude_po_id: params[:exclude_purchase_order_id].presence)
    render json: { payload: hit }
  end

  # 按供应商分组的结构化数据，供前端列出供应商、勾选要导哪几家、以及看/改各家抬头。
  def export_data
    render json: { payload: Mes::PoSupplierExport.new(@purchase_order, bill_entities: bill_entities_param).payload }
  end

  private

  # 没过审就不许预览/导出。
  # 原先 export? 只看「能不能看金额」，不看审批状态——采购员可以在「待总经理审批」时
  # 直接把采购单导出发给供应商，老板还以为自己在把关。审批形同虚设。
  # 拦在控制器而不是策略里：策略管的是「这个人有没有这个权限」，这里管的是
  # 「这张单到没到可以对外的状态」，两回事。
  # 关不关得掉由模型说了算，失败要把原话吐给采购（「已经收过货」之类），别兜成通用报错。
  def render_after
    yield
    render 'api/v1/accounts/mes/purchase_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def ensure_approved_before_export!
    return if @purchase_order.approved?

    render json: { error: "采购单 #{@purchase_order.po_no} 还没通过审批（当前：#{APPROVAL_LABELS[@purchase_order.approval_status]}），" \
                          '审批通过后才能预览/导出发给供应商' },
           status: :unprocessable_entity
  end

  APPROVAL_LABELS = {
    'DRAFT' => '草稿未提交', 'PENDING_GM' => '待总经理审批', 'REJECTED' => '已驳回', 'APPROVED' => '已通过'
  }.freeze

  # bill_entities[13]=liontek → { '13' => 'liontek' }；服务层负责校验主体合法性。
  def bill_entities_param
    raw = params[:bill_entities]
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
  end

  # 列表筛选（列筛选 / 异常 / 搜索）收在一处，index 只管取数与分页。
  def index_scope
    scope = scoped_by_approver_or_order_owner(scoped_by_product_line(Current.account.mes_purchase_orders))
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = Mes::PurchaseOrderFilter.apply(scope, params)
    scope = scope.where(has_exception: true) if params[:exception] == 'true'
    scope = apply_search(scope, params[:q]) if params[:q].present?
    scoped_by_created_range(scope)
  end

  # 采购审批人（不兼 MES 岗的副总经理等）看他负责产线的采购单全部。
  # 不能走 scoped_by_order_owner：那是按 CRM 团队收口的，而审批人团队里没有采购员，
  # 收完就是 0 条——页面打得开、一张单都没有，等于批不了。
  def scoped_by_approver_or_order_owner(scope)
    au = Current.account_user
    return scoped_by_order_owner(scope) if au.nil? || au.mes_staff?

    lines = Mes::PurchaseOrder.approver_lines_for(Current.account, au.user_id)
    return scoped_by_order_owner(scope) if lines.empty?

    lines.any?(&:blank?) ? scope : scope.where(product_line: lines)
  end

  # 每页条数：默认沿用 RESULTS_PER_PAGE(15) 供列表分页；调用方（如入库单的采购单下拉）
  # 需要一次性拿到全部采购单时可传 per_page，封顶 500 防止拉全表。

  # 采购单搜索：单号 / 归属人(采购制单人 + 生产订单归属业务员) / 生产订单(单号+品名) /
  # 供应商 / 物料编码(产品SKU/物料料号)。明细维度用 EXISTS 子查询（避免 join 造成行重复、count 失真）。
  # 「归属人」列显示的是生产订单归属业务员(po.owner)，故必须一并匹配 pou.name。
  def apply_search(scope, raw)
    q = "%#{raw.strip}%"
    scope.where(
      'mes_purchase_orders.po_no ILIKE :q
       OR EXISTS (SELECT 1 FROM users u
                  WHERE u.id = mes_purchase_orders.owner_id AND u.name ILIKE :q)
       OR EXISTS (SELECT 1 FROM mes_production_orders po
                  LEFT JOIN users pou ON pou.id = po.owner_id
                  WHERE po.id = mes_purchase_orders.production_order_id
                    AND (po.order_no ILIKE :q OR po.product_name ILIKE :q OR pou.name ILIKE :q))
       OR EXISTS (SELECT 1 FROM mes_purchase_items pi
                  LEFT JOIN mes_suppliers s ON s.id = pi.mes_supplier_id
                  LEFT JOIN crm_products p ON p.id = pi.crm_product_id
                  LEFT JOIN mes_materials m ON m.id = pi.mes_material_id
                  WHERE pi.purchase_order_id = mes_purchase_orders.id
                    AND (s.name ILIKE :q OR p.sku ILIKE :q OR p.name ILIKE :q OR m.material_no ILIKE :q))',
      q: q
    )
  end

  def fetch_purchase_order
    @purchase_order = Current.account.mes_purchase_orders.find(params[:id])
  end

  # DocumentReturnable 钩子
  def returnable_record = Current.account.mes_purchase_orders.find(params[:id])

  def render_returnable(record)
    @purchase_order = record
    render 'api/v1/accounts/mes/purchase_orders/show'
  end

  def check_authorization
    authorize(Mes::PurchaseOrder)
  end

  # 本单当前审批人本人，或管理员代批。
  def ensure_po_approver!
    return if Current.account_user.administrator?
    return if @purchase_order.gm_id.present? && @purchase_order.gm_id == current_user.id

    render json: { error: '这张单不在你这里审批' }, status: :unauthorized
  end

  def purchase_order_params
    params.require(:purchase_order).permit(
      # 单号允许手工填（两账并行期要对上金蝶的号）。**只在新建时放行**——
      # 改已生效单据的号会让纸质单、下游单据和 ERP 全部对不上。留空则自动生成。
      *(action_name == 'create' ? [:po_no] : []),
      :production_order_id, :product_line, :status, :expected_date, :follow_up_date, :delivery_date,
      :has_exception, :exception_note, :owner_id, :remark, :internal_remark,
      extra_production_order_ids: [],
      purchase_items_attributes: [
        :id, :item_type, :mes_material_id, :crm_product_id, :mes_supplier_id, :arrival_date,
        :qty, :unit, :rate_micros, :price_tax_included, :received_qty, :aux_attribute_name, :remark, :_destroy,
        # 行内附图：传 signed_id 数组，整组替换（前端每次给这一行完整的列表）
        { images: [] }
      ]
    )
  end
end
