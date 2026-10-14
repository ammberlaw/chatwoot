# 实时库存：现货多少、在途多少、已经被别的在产订单排掉多少。
#
# 「这个型号现在有货吗、能几天交」是业务员报交期前必问的。
# 光看结存数会报错交期——结存 100 不代表能卖 100，别的单早排上了
# （占用量复用 Mes::MaterialCommitment，与新建生产任务单那个感叹号同一口径）。
#
# ⚠️ 只给数量，不给采购价/成本——销售端不可见。
class Crm::Agent::Tools::StockLookup < Crm::Agent::Tools::Base
  description '查实时库存：按产品编码/名称或物料编码查现货结存、在途（已下采购未到）、以及已被其他在产订单排用的数量，用来判断能不能接单、报多久交期。'
  param :keyword, desc: '产品编码、产品名称或物料编码'
  param :limit, type: 'integer', desc: '最多返回几条，默认 10', required: false

  def execute(keyword:, limit: 10)
    kw = keyword.to_s.strip
    return '请给产品编码、名称或物料编码。' if kw.blank?

    rows = (product_rows(kw) + material_rows(kw)).first([limit.to_i, 25].min)
    return "库存里没查到和「#{kw}」相关的产品或物料。" if rows.empty?

    "【实时库存】\n#{rows.join("\n")}"
  end

  private

  def balances = scope.account.mes_stock_balances

  def product_rows(keyword)
    products = scope.account.crm_products
                    .where('sku ILIKE :t OR name ILIKE :t', t: "%#{keyword}%").limit(15).to_a
    return [] if products.empty?

    totals = balances.where(crm_product_id: products.map(&:id)).group(:crm_product_id).sum(:qty)
    on_order = balances.where(crm_product_id: products.map(&:id)).group(:crm_product_id).sum(:on_order_qty)
    products.map { |p| product_line(p, totals, on_order) }
  end

  def product_line(product, totals, on_order)
    held = committed[product.sku].to_d
    on_hand = totals[product.id].to_d
    "成品 #{product.sku}｜#{product.name}｜现货 #{qty(on_hand, product.unit)}｜" \
      "在途 #{qty(on_order[product.id], product.unit)}｜别单已排用 #{qty(held, product.unit)}｜" \
      "可用 #{qty(on_hand - held, product.unit)}"
  end

  def material_rows(keyword)
    materials = scope.account.mes_materials
                     .where('material_no ILIKE :t OR name ILIKE :t', t: "%#{keyword}%").limit(15).to_a
    return [] if materials.empty?

    totals = balances.where(mes_material_id: materials.map(&:id)).group(:mes_material_id).sum(:qty)
    on_order = balances.where(mes_material_id: materials.map(&:id)).group(:mes_material_id).sum(:on_order_qty)
    materials.map { |m| material_line(m, totals, on_order) }
  end

  def material_line(material, totals, on_order)
    held = committed[material.material_no].to_d
    on_hand = totals[material.id].to_d
    "物料 #{material.material_no}｜#{material.name}｜现货 #{qty(on_hand, material.unit)}｜" \
      "在途 #{qty(on_order[material.id], material.unit)}｜别单已排用 #{qty(held, material.unit)}｜" \
      "可用 #{qty(on_hand - held, material.unit)}"
  end

  # 被在产订单排掉的量，按料号/编码对。只算一次，两段都用。
  def committed
    @committed ||= Mes::MaterialCommitment.by_material_no(scope.account)
  end

  def qty(value, unit) = "#{fnum(value)} #{unit.presence || ''}".strip
end
