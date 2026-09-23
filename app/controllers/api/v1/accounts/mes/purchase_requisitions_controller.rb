class Api::V1::Accounts::Mes::PurchaseRequisitionsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_requisition, only: [:show, :update, :destroy, :submit, :cancel, :convert]

  COLUMN_FILTERS = { status: :status, purpose: :purpose, production_order_id: :production_order_id }.freeze

  def index
    scope = scoped_by_product_line(Current.account.mes_purchase_requisitions)
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = scope.where('req_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @requisitions_count = scope.count
    @requisitions = scope.order(created_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @requisition = Current.account.mes_purchase_requisitions.new(
      requisition_params.merge(owner_id: current_user.id)
    )
    @requisition.fallback_product_line = current_product_line
    @requisition.save!
    render 'api/v1/accounts/mes/purchase_requisitions/show'
  end

  def update
    @requisition.update!(requisition_params)
    render 'api/v1/accounts/mes/purchase_requisitions/show'
  end

  # 提交（DRAFT → OPEN）：无审批，提交后采购即可见、可转采购单。
  def submit
    @requisition.update!(status: 'OPEN') if @requisition.draft?
    render 'api/v1/accounts/mes/purchase_requisitions/show'
  end

  def cancel
    @requisition.update!(status: 'CANCELLED')
    render 'api/v1/accounts/mes/purchase_requisitions/show'
  end

  # 转采购单（拆批 + 改量）：采购选若干行、各填本批采购量，生成一张采购单并累加 ordered_qty、
  # 重算申请单状态（可多次转，实现分批采购）。
  def convert
    authorize(Mes::PurchaseRequisition, :convert?)
    lines = convert_lines
    raise StandardError, '请至少选择一行并填写本批采购量' if lines.blank?

    po = build_purchase_order_from(lines)
    ActiveRecord::Base.transaction do
      po.save!
      lines.each { |ln| ln[:item].increment!(:ordered_qty, ln[:qty]) }
      @requisition.recompute_order_status!
    end
    render json: { payload: { purchase_order_id: po.id, po_no: po.po_no, requisition_status: @requisition.reload.status } }
  end

  def destroy
    @requisition.destroy!
    head :ok
  end

  private

  def fetch_requisition
    @requisition = Current.account.mes_purchase_requisitions.find(params[:id])
  end

  def check_authorization
    authorize(Mes::PurchaseRequisition)
  end

  # 转采购入参：lines = [{ requisition_item_id, qty, mes_supplier_id? }]。
  # 归一为 { item, qty, supplier_id }，过滤无效行（无量/量<=0/找不到明细）。
  def convert_lines
    (params[:lines] || []).filter_map do |ln|
      item = @requisition.requisition_items.find_by(id: ln[:requisition_item_id])
      qty = ln[:qty].to_d
      next if item.nil? || qty <= 0

      { item: item, qty: qty, supplier_id: ln[:mes_supplier_id].presence || item.mes_supplier_id }
    end
  end

  def build_purchase_order_from(lines)
    po = Current.account.mes_purchase_orders.new(
      production_order_id: @requisition.production_order_id,
      purchase_requisition_id: @requisition.id,
      owner_id: current_user.id,
      product_line: @requisition.product_line,
      expected_date: params[:expected_date].presence,
      delivery_date: params[:delivery_date].presence,
      remark: params[:remark].presence
    )
    po.fallback_product_line = current_product_line
    lines.each do |ln|
      it = ln[:item]
      po.purchase_items.new(
        item_type: it.item_type, mes_material_id: it.mes_material_id, crm_product_id: it.crm_product_id,
        mes_supplier_id: ln[:supplier_id], unit: it.unit, qty: ln[:qty], rate_micros: 0
      )
    end
    po
  end

  def requisition_params
    params.require(:purchase_requisition).permit(
      :production_order_id, :purpose, :status, :expected_date, :remark,
      requisition_items_attributes: [
        :id, :item_type, :mes_material_id, :crm_product_id, :mes_supplier_id,
        :material_no, :material_name, :specification, :unit,
        :required_qty, :suggested_qty, :remark, :_destroy
      ]
    )
  end
end
