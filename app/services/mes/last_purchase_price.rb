# 同一颗料、同一个供应商，上次下单是多少钱。
#
# 采购原话：「同一个物料同一个供应商第一次下单我填了单价，第二次我下单填了供应商，
# 单价要会自动显示出来我最新的单价，不然谁都记不住那么多物料单价」。
#
# 只认**审批通过**的采购单（她点名的条件）：没过审的单价还可能被老板打回来改，
# 拿它当下次的参考会把错价一路传下去。作废单同理不算。
# 口径与 Mes::MaterialPriceResolver 的「最近采购价」一致，区别是这里**还要分供应商**
# ——同一颗料不同供应商价格不一样，不分供应商带出来的价是错的。
class Mes::LastPurchasePrice
  def self.for(account:, supplier_id:, crm_product_id: nil, mes_material_id: nil)
    return nil unless askable?(account, supplier_id, crm_product_id, mes_material_id)

    item = scope(account, supplier_id, crm_product_id, mes_material_id).first
    item && payload(item)
  end

  def self.askable?(account, supplier_id, crm_product_id, mes_material_id)
    account.present? && supplier_id.present? && (crm_product_id.present? || mes_material_id.present?)
  end
  private_class_method :askable?

  def self.payload(item)
    { rate_micros: item.rate_micros,
      price_tax_included: item.price_tax_included,
      po_no: item.purchase_order&.po_no,
      # 单据日期就是建单时间（表上没有独立的 doc_date，列表那列也是这么出的）
      ordered_at: item.purchase_order&.created_at }
  end
  private_class_method :payload

  def self.scope(account, supplier_id, crm_product_id, mes_material_id)
    rel = Mes::PurchaseItem.joins(:purchase_order).includes(:purchase_order)
                           .where(account_id: account.id, mes_supplier_id: supplier_id)
                           .where(mes_purchase_orders: { approval_status: Mes::MaterialPriceResolver::APPROVED_PO })
                           .where.not(mes_purchase_orders: { status: Mes::MaterialPriceResolver::VOID_PO_STATUS })
                           .where('mes_purchase_items.rate_micros > 0')
    rel = if mes_material_id.present?
            rel.where(mes_material_id: mes_material_id)
          else
            rel.where(crm_product_id: crm_product_id)
          end
    # 最近一张：按建单时间倒序（单据日期即建单时间，见 _mes_purchase_order 的 doc_date）。
    rel.order('mes_purchase_orders.created_at DESC')
  end
  private_class_method :scope
end
