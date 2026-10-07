class Api::V1::Accounts::Mes::StockBalancesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def index
    @balances = filtered_scope.to_a
    @balances = @balances.select(&:short?) if params[:short] == 'true'
    # 成品预占（现货出库「提交即预占」）：可用 = 结存 − 预占。
    @reserved = Mes::Shipment.reserved_qty_map(Current.account)
  end

  private

  def filtered_scope
    scope = scoped_by_product_line(
      Current.account.mes_stock_balances.includes(:mes_material, :crm_product, :warehouse).where('qty <> 0')
    )
    scope = scope.where(item_type: params[:item_type]) if params[:item_type].present?
    scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
    scope = search(scope) if params[:q].present?
    scope
  end

  # 按编码/名称/规格找货。库存实际按产品档案记，物料主数据基本是空的，
  # 但老数据里有挂物料的行，两张表都带上。
  def search(scope)
    term = "%#{params[:q].to_s.strip}%"
    scope.left_joins(:crm_product, :mes_material)
         .where('crm_products.sku ILIKE :t OR crm_products.name ILIKE :t OR crm_products.specification ILIKE :t ' \
                'OR mes_materials.material_no ILIKE :t OR mes_materials.name ILIKE :t', t: term)
  end

  def check_authorization
    authorize(Mes::StockBalance)
  end
end
