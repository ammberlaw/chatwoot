# 采购单列表的表头漏斗（对标金蝶：每个列头一个筛选入口）。
#
# 条件一律发后端算，不在前端过滤本页：采购单常年几十上百张、列表分页，
# 前端只过滤当前页的话第 2 页往后的命中全看不见。
#
# 明细维度（供应商/物料编码/名称/规格）统统用 EXISTS 子查询，**不 join**：
# 一张单十几行料，join 会把单据行复制十几份，count 和分页全失真。
class Mes::PurchaseOrderFilter
  # 参数名 → 构造条件的方法
  FILTERS = {
    po_no: :po_no_like, supplier: :supplier_like, order_no: :order_no_like,
    item_code: :item_code_like, item_name: :item_name_like, item_spec: :item_spec_like
  }.freeze

  def self.apply(scope, params)
    new(params).apply(scope)
  end

  def initialize(params)
    @params = params
  end

  def apply(scope)
    FILTERS.each do |param, builder|
      raw = @params[param]
      scope = send(builder, scope, "%#{raw.strip}%") if raw.present?
    end
    scope
  end

  private

  def po_no_like(scope, pattern) = scope.where('mes_purchase_orders.po_no ILIKE ?', pattern)

  def order_no_like(scope, pattern)
    scope.where('EXISTS (SELECT 1 FROM mes_production_orders po
                 WHERE po.id = mes_purchase_orders.production_order_id AND po.order_no ILIKE ?)', pattern)
  end

  def supplier_like(scope, pattern)
    scope.where('EXISTS (SELECT 1 FROM mes_purchase_items pi
                 JOIN mes_suppliers s ON s.id = pi.mes_supplier_id
                 WHERE pi.purchase_order_id = mes_purchase_orders.id AND s.name ILIKE ?)', pattern)
  end

  # 物料三列两边都要看：一张采购单里成品走产品档案(crm_products)、原料走物料档案(mes_materials)。
  def item_code_like(scope, pattern)
    item_exists(scope, 'p.sku ILIKE :q OR m.material_no ILIKE :q', pattern)
  end

  def item_name_like(scope, pattern)
    item_exists(scope, 'p.name ILIKE :q OR m.name ILIKE :q', pattern)
  end

  def item_spec_like(scope, pattern)
    item_exists(scope, 'p.specification ILIKE :q OR m.specification ILIKE :q', pattern)
  end

  def item_exists(scope, condition, pattern)
    scope.where(
      "EXISTS (SELECT 1 FROM mes_purchase_items pi
               LEFT JOIN crm_products p ON p.id = pi.crm_product_id
               LEFT JOIN mes_materials m ON m.id = pi.mes_material_id
               WHERE pi.purchase_order_id = mes_purchase_orders.id AND (#{condition}))", q: pattern
    )
  end
end
