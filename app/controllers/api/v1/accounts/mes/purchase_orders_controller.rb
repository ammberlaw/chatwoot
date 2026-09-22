class Api::V1::Accounts::Mes::PurchaseOrdersController < Api::V1::Accounts::Mes::BaseController
  include Api::V1::Accounts::Mes::DocumentReturnable

  before_action :check_authorization
  before_action :fetch_purchase_order, only: [:show, :update, :destroy, :export, :export_data, :submit, :approve, :reject]

  COLUMN_FILTERS = { status: :status, production_order_id: :production_order_id }.freeze

  def index
    scope = index_scope
    @purchase_orders_count = scope.count
    @purchase_orders = scope.order(created_at: :desc).page(page_param).per(per_page_param)
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

  # 提交总经理审批（草稿/被驳回可提交）。
  def submit
    @purchase_order.submit_for_approval!(current_user)
    render 'api/v1/accounts/mes/purchase_orders/show'
  end

  # 总经理通过 → 生效，累加在途库存。
  def approve
    @purchase_order.gm_approve!(current_user, comment: params[:comment])
    render 'api/v1/accounts/mes/purchase_orders/show'
  end

  # 总经理驳回 → 退回制单人。
  def reject
    @purchase_order.reject_approval!(current_user, reason: params[:reason])
    render 'api/v1/accounts/mes/purchase_orders/show'
  end

  # 待我审批的采购单（总经理待办箱）。
  def approval_inbox
    scope = Current.account.mes_purchase_orders.awaiting_gm_for(current_user.id)
    @purchase_orders_count = scope.count
    @purchase_orders = scope.order(submitted_at: :asc).page(page_param).per(RESULTS_PER_PAGE)
    render 'api/v1/accounts/mes/purchase_orders/index'
  end

  # BOM 算料：按生产订单的 BOM 展开采购需求，供采购单预填。
  def requirement
    production_order = Current.account.mes_production_orders.find(params[:production_order_id])
    # category 可选：MACHINE 主料(整机料) / PACKAGING 辅料(包装料)——支持两个采购员分料建单。
    render json: { payload: production_order.material_requirements(category: params[:category].presence) }
  end

  # 按供应商拆单导出 PDF：各供应商的料各成一份、填公司原始模板（含公章）→ Gotenberg 转 1:1 PDF。
  # 单个供应商直接下 PDF；多个供应商打包 zip（每家一份 PDF）。抬头/税口径按各供应商 bill_entity 自动选。
  def export
    doc = Mes::PoSupplierExport.new(@purchase_order).to_pdf_download
    send_data doc[:io].read, filename: doc[:filename], type: doc[:content_type]
  rescue Mes::GotenbergClient::ConversionError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  # 按供应商分组的结构化数据，供前端渲染各供应商的 PO 版式并导出 PDF（每供应商一份、打包 zip）。
  def export_data
    render json: { payload: Mes::PoSupplierExport.new(@purchase_order).payload }
  end

  private

  # 列表筛选（列筛选 / 异常 / 搜索）收在一处，index 只管取数与分页。
  def index_scope
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_purchase_orders))
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = scope.where(has_exception: true) if params[:exception] == 'true'
    scope = apply_search(scope, params[:q]) if params[:q].present?
    scope
  end

  # 每页条数：默认沿用 RESULTS_PER_PAGE(15) 供列表分页；调用方（如入库单的采购单下拉）
  # 需要一次性拿到全部采购单时可传 per_page，封顶 500 防止拉全表。
  MAX_PER_PAGE = 500
  def per_page_param
    n = params[:per_page].to_i
    n = RESULTS_PER_PAGE if n <= 0
    [n, MAX_PER_PAGE].min
  end

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

  def purchase_order_params
    params.require(:purchase_order).permit(
      :production_order_id, :product_line, :status, :expected_date, :follow_up_date, :delivery_date,
      :has_exception, :exception_note, :owner_id, :remark,
      purchase_items_attributes: [
        :id, :item_type, :mes_material_id, :crm_product_id, :mes_supplier_id, :arrival_date,
        :qty, :unit, :rate_micros, :price_tax_included, :received_qty, :remark, :_destroy
      ]
    )
  end
end
