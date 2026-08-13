class Api::V1::Accounts::Mes::SerialNumbersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def index
    scope = scoped_by_product_line(Current.account.mes_serial_numbers.includes(:crm_product, :production_order))
    scope = scope.where(production_order_id: params[:production_order_id]) if params[:production_order_id].present?
    scope = scope.where('sn ILIKE ?', "%#{params[:q].strip}%") if params[:q].present?
    @serial_numbers_count = scope.count
    @serial_numbers = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  # 按工单登记 SN：给定 sns 明细则逐条建，否则按 count 生成「工单号-序号」。
  def create
    order = Current.account.mes_production_orders.find(params[:production_order_id])
    codes = provided_codes.presence || generated_codes(order)
    created = codes.filter_map do |code|
      Current.account.mes_serial_numbers.create(sn: code, production_order: order, crm_product: order.crm_product).persisted? ? code : nil
    end
    render json: { registered: created.size }
  end

  def destroy
    Current.account.mes_serial_numbers.find(params[:id]).destroy!
    head :ok
  end

  # 追溯：SN → 工单 → BOM/物料、客户、出库。接售后 RMA。
  def trace
    sn = Current.account.mes_serial_numbers.includes(production_order: [:bom, :crm_sales_order]).find_by(sn: params[:sn].to_s.strip)
    return render json: { error: '未找到该序列号' }, status: :not_found if sn.nil?

    order = sn.production_order
    shipment = order && Current.account.mes_shipments.where(production_order_id: order.id).order(:id).last
    render json: { payload: trace_payload(sn, order, shipment) }
  end

  private

  def check_authorization
    authorize(Mes::SerialNumber)
  end

  def provided_codes
    raw = params[:sns]
    list = raw.is_a?(Array) ? raw : raw.to_s.split(/[\s,]+/)
    list.map(&:strip).reject(&:blank?)
  end

  def generated_codes(order)
    count = params[:count].to_i
    return [] if count <= 0

    existing = Current.account.mes_serial_numbers.where(production_order_id: order.id).count
    (1..count).map { |i| format('%<base>s-%<seq>04d', base: order.order_no, seq: existing + i) }
  end

  def trace_payload(sn, order, shipment)
    {
      sn: sn.sn, status: sn.status, product_name: sn.crm_product&.name,
      production_order: order && { order_no: order.order_no, qty: order.qty, produced_qty: order.produced_qty, stage: order.stage },
      bom: order&.bom && { bom_no: order.bom.bom_no, materials: order.bom.bom_items.map { |i| i.mes_material&.name }.compact },
      sales_order_no: order&.crm_sales_order&.order_no,
      customer_name: order&.crm_sales_order&.crm_customer&.name,
      shipment: shipment && { shipment_no: shipment.shipment_no, shipped_at: shipment.shipped_at }
    }
  end
end
