# 委外加工单 + 它派生的三张库存单（发料 / 产品入库 / 退料）。
# 单据之间的数量关系都在 Mes::OutsourceDocumentService 里算，这里只管进出参数和权限。
class Api::V1::Accounts::Mes::OutsourceOrdersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_order, only: [:show, :update, :destroy, :confirm, :close,
                                     :issue, :receipt, :return_materials, :generate_fee]

  COLUMN_FILTERS = { status: :status, mes_supplier_id: :mes_supplier_id,
                     production_order_id: :production_order_id }.freeze

  # 表头逐列筛选。放后端是因为列表分页：前端只过滤本页，第 2 页往后的命中就全看不见了。
  COLUMN_LIKE_FILTERS = {
    col_no: ->(scope, v) { scope.where('mes_outsource_orders.order_no ILIKE ?', "%#{v}%") },
    col_supplier: lambda { |scope, v|
      scope.where(mes_supplier_id: Mes::Supplier.where('name ILIKE ?', "%#{v}%").select(:id))
    },
    col_product: lambda { |scope, v|
      scope.where(crm_product_id: Crm::Product.where('name ILIKE :t OR sku ILIKE :t', t: "%#{v}%").select(:id))
    },
    col_mo: lambda { |scope, v|
      scope.where(production_order_id: Mes::ProductionOrder.where('order_no ILIKE ?', "%#{v}%").select(:id))
    },
    q: lambda { |scope, v|
      scope.where(
        'mes_outsource_orders.order_no ILIKE :t OR mes_outsource_orders.remark ILIKE :t ' \
        'OR mes_outsource_orders.mes_supplier_id IN (SELECT id FROM mes_suppliers WHERE name ILIKE :t) ' \
        'OR mes_outsource_orders.crm_product_id IN (SELECT id FROM crm_products WHERE name ILIKE :t OR sku ILIKE :t)',
        t: "%#{v}%"
      )
    }
  }.freeze

  def index
    scope = scoped_by_product_line(Current.account.mes_outsource_orders)
    COLUMN_FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = scoped_by_created_range(scope)
    scope = apply_column_filters(scope)
    @outsource_orders_count = scope.count
    @outsource_orders = scope.includes(:mes_supplier, :crm_product, :production_order, :mes_warehouse, :owner,
                                       outsource_materials: [:mes_material, :crm_product],
                                       stock_entries: :stock_entry_items)
                             .order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  # 从生产订单转委外（本模块唯一的建单入口，见 Mes::OutsourceOrderBuilder 的说明）。
  def create
    production_order = Current.account.mes_production_orders.find(params[:production_order_id])
    @outsource_order = Mes::OutsourceOrderBuilder
                       .new(account: Current.account, actor: current_user)
                       .from_production_order(production_order, outsource_order_params.to_h)
    render 'api/v1/accounts/mes/outsource_orders/show'
  rescue Mes::OutsourceOrderBuilder::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @outsource_order.update!(outsource_order_params)
    render 'api/v1/accounts/mes/outsource_orders/show'
  end

  def destroy
    return render json: { error: '已经发过料或收过货的加工单不能删，请走关闭' }, status: :unprocessable_entity if touched?

    @outsource_order.destroy!
    head :ok
  end

  def confirm
    @outsource_order.update!(status: 'CONFIRMED')
    render 'api/v1/accounts/mes/outsource_orders/show'
  end

  def close
    @outsource_order.update!(status: 'CLOSED')
    render 'api/v1/accounts/mes/outsource_orders/show'
  end

  # 生成委外发料单（原料仓 → 委外仓）。不传 rows 就按「还没发的标准用量」整单带出。
  def issue
    render_document { service.build_issue(rows: issue_rows) }
  end

  # 生成委外产品入库单（产出进成品仓 + 按标准用量倒冲委外仓的料）。
  def receipt
    render_document { service.build_receipt(qty: params[:qty], to_warehouse_id: params[:to_warehouse_id]) }
  end

  # 生成委外退料单（委外仓 → 原料仓 / 不良品仓）。
  def return_materials
    render_document do
      service.build_return(rows: return_rows, to_warehouse_id: params[:to_warehouse_id])
    end
  end

  # 生成加工费应付。手动动作：财务跟加工厂对完账再点（同采购「先对账再建账」）。
  def generate_fee
    payable = Mes::OutsourceFeePayableService.new(@outsource_order).sync!
    render json: { payload: { payable_no: payable.payable_no, total_amount_micros: payable.total_amount_micros } }
  end

  private

  def service
    Mes::OutsourceDocumentService.new(order: @outsource_order, actor: current_user)
  end

  def render_document
    entry = yield
    render json: { payload: { id: entry.id, entry_no: entry.entry_no } }
  rescue Mes::OutsourceDocumentService::Error, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def issue_rows
    rows = params[:rows]
    return nil if rows.blank?

    rows.map do |row|
      material = @outsource_order.outsource_materials.find(row[:material_id])
      { material: material, qty: row[:qty].to_d }
    end
  end

  def return_rows
    Array(params[:rows]).map { |row| { material_id: row[:material_id], qty: row[:qty] } }
  end

  def touched?
    Current.account.mes_stock_entries.exists?(outsource_order_id: @outsource_order.id, status: 'POSTED')
  end

  def apply_column_filters(scope)
    COLUMN_LIKE_FILTERS.each do |param, apply|
      scope = apply.call(scope, params[param].to_s.strip) if params[param].present?
    end
    scope
  end

  def fetch_order
    @outsource_order = Current.account.mes_outsource_orders.find(params[:id])
  end

  def check_authorization
    authorize(Mes::OutsourceOrder)
  end

  def outsource_order_params
    params.fetch(:outsource_order, {}).permit(
      :mes_supplier_id, :mes_warehouse_id, :to_warehouse_id, :qty, :unit, :doc_date, :delivery_date,
      :fee_rate_micros, :fee_tax_included, :tax_rate, :remark, :status,
      outsource_materials_attributes: [:id, :mes_material_id, :crm_product_id, :unit, :qty_numerator,
                                       :qty_denominator, :loss_rate, :from_warehouse_id, :remark, :_destroy]
    )
  end
end
