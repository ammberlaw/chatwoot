# 这颗料上次下单：多少钱、给了哪个供应商。
#
# 采购原话：「同一个物料同一个供应商第一次下单我填了单价，第二次我下单填了供应商，
# 单价要会自动显示出来我最新的单价，不然谁都记不住那么多物料单价」，
# 后来又加一条：「新建采购单输入料号自动带出上一个订单单价（已审核订单）和供应商」。
#
# 所以两种问法都支持：
#   · 只给料号 → 返回最近一张已审核单上的**供应商 + 单价**（新建时输完料号就全带出来）
#   · 料号 + 供应商 → 返回**这家**供应商上次的价（同一颗料不同供应商价不一样，
#     已经选定供应商时不能拿别家的价顶上）
#
# 只认**审批通过**的采购单（她点名的条件）：没过审的单价还可能被老板打回来改，
# 拿它当下次的参考会把错价一路传下去。作废单同理不算。
# 口径与 Mes::MaterialPriceResolver 的「最近采购价」一致。
class Mes::LastPurchasePrice
  def self.for(account:, crm_product_id: nil, mes_material_id: nil, supplier_id: nil)
    return nil if account.blank? || (crm_product_id.blank? && mes_material_id.blank?)

    item = scope(account, supplier_id, crm_product_id, mes_material_id).first
    item && payload(item)
  end

  def self.payload(item)
    { rate_micros: item.rate_micros,
      price_tax_included: item.price_tax_included,
      mes_supplier_id: item.mes_supplier_id,
      supplier_name: item.mes_supplier&.name,
      po_no: item.purchase_order&.po_no,
      # 单据日期就是建单时间（表上没有独立的 doc_date，列表那列也是这么出的）
      ordered_at: item.purchase_order&.created_at }
  end
  private_class_method :payload

  def self.scope(account, supplier_id, crm_product_id, mes_material_id)
    rel = base_scope(account)
    rel = rel.where(mes_supplier_id: supplier_id) if supplier_id.present?
    rel = if mes_material_id.present?
            rel.where(mes_material_id: mes_material_id)
          else
            rel.where(crm_product_id: crm_product_id)
          end
    # 最近一张：按建单时间倒序（单据日期即建单时间，见 _mes_purchase_order 的 doc_date）。
    rel.order('mes_purchase_orders.created_at DESC')
  end
  private_class_method :scope

  # 只问供应商也要有：没选供应商时带出来的那家必须是真下过单的。
  def self.base_scope(account)
    Mes::PurchaseItem.joins(:purchase_order).includes(:purchase_order, :mes_supplier)
                     .where(account_id: account.id)
                     .where(mes_purchase_orders: { approval_status: Mes::MaterialPriceResolver::APPROVED_PO })
                     .where.not(mes_purchase_orders: { status: Mes::MaterialPriceResolver::VOID_PO_STATUS })
                     .where('mes_purchase_items.rate_micros > 0')
                     .where.not(mes_supplier_id: nil)
  end
  private_class_method :base_scope
end
