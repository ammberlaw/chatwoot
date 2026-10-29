# 采购单每一行的价，跟这颗料上次买多少比。给**审批人**用。
#
# 用户 2026-10-29 提：销售订单审核和出库审核要有比价提示，采购单和采购单审批也要有。
#
# 录单时本来就有提示（新建采购单页的 priceDelta，走 Mes::LastPurchasePrice 逐行查），
# 但那个数**不参与提交**——到了审批页就没了，老板看到的只是一个光秃秃的单价。
# 这里是同一套口径的批量版：整单一次查完，不逐行往返。
#
# 口径与 Mes::LastPurchasePrice 完全一致（只认审批通过、未作废、有价的单，排除本单自己），
# 加两条审批页特有的：
#   · 同供应商优先 —— 同一颗料不同供应商价本来就不一样，拿别家的价比会天天误报；
#     这家没买过才退回「任意供应商最近一次」，并在提示里注明
#   · 税别不同不比 —— 含税价和不含税价直接比是错的（录单页那边早就这么做了，
#     写着「与上次税别不同，未作比较」）
#
# 阈值与销售那套一致：±10% 提醒、±30% 标红（用户 2026-10-29 定）。
class Mes::PurchasePriceBenchmark
  WARN_RATIO = 0.10
  ALERT_RATIO = 0.30

  Result = Struct.new(:last_rate_micros, :diff_ratio, :level, :scope_label,
                      :po_no, :ordered_at, :supplier_name, :skip_reason,
                      keyword_init: true)

  def initialize(account)
    @account = account
  end

  # => { purchase_item_id => Result }
  def for_order(purchase_order)
    items = purchase_order.purchase_items.to_a
    return {} if items.empty?

    history = history_for(items, exclude_po_id: purchase_order.id)
    items.each_with_object({}) do |item, out|
      result = result_for(item, history)
      out[item.id] = result if result
    end
  end

  private

  def result_for(item, history)
    return nil if item.rate_micros.to_i <= 0

    hit = pick(history[key_of(item)], item.mes_supplier_id)
    return nil if hit.nil?

    # 含税/不含税混比是错的，宁可不提示（同录单页的做法）。
    return Result.new(skip_reason: '与上次税别不同，未作比较') if tax_basis_differs?(item, hit)

    compare(item.rate_micros, hit)
  end

  def tax_basis_differs?(item, hit)
    !hit[:price_tax_included].nil? && hit[:price_tax_included] != item.price_tax_included
  end

  def compare(rate, hit)
    last = hit[:rate_micros].to_i
    ratio = (rate - last) / last.to_f
    Result.new(
      last_rate_micros: last, diff_ratio: ratio.round(4), level: level_of(ratio),
      scope_label: hit[:same_supplier] ? '这家上次' : '最近一次',
      po_no: hit[:po_no], ordered_at: hit[:ordered_at], supplier_name: hit[:supplier_name]
    )
  end

  def level_of(ratio)
    abs = ratio.abs
    return 'alert' if abs >= ALERT_RATIO
    return 'warn' if abs >= WARN_RATIO

    'normal'
  end

  # 同供应商的优先；这家没买过才拿任意供应商最近那条。
  def pick(entries, supplier_id)
    return nil if entries.blank?

    entries.find { |e| e[:mes_supplier_id] == supplier_id }&.merge(same_supplier: true) ||
      entries.first&.merge(same_supplier: false)
  end

  # 料行挂物料档就按物料 id，否则按商品档 id（同 MaterialPriceResolver 的归一化做法）。
  def key_of(item)
    item.mes_material_id.presence&.then { |id| "m#{id}" } ||
      item.crm_product_id.presence&.then { |id| "p#{id}" }
  end

  # { key => [按时间倒序的历史] }。一次查完这张单用到的所有料。
  def history_for(items, exclude_po_id:)
    material_ids = items.filter_map(&:mes_material_id).uniq
    product_ids = items.filter_map(&:crm_product_id).uniq
    return {} if material_ids.empty? && product_ids.empty?

    rows = scope(material_ids, product_ids).where.not(purchase_order_id: exclude_po_id)
    rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, out|
      out[key_of(row)] << entry_of(row)
    end
  end

  def entry_of(row)
    { rate_micros: row.rate_micros, price_tax_included: row.price_tax_included,
      mes_supplier_id: row.mes_supplier_id, supplier_name: row.mes_supplier&.name,
      po_no: row.purchase_order&.po_no, ordered_at: row.purchase_order&.created_at }
  end

  def scope(material_ids, product_ids)
    Mes::PurchaseItem.joins(:purchase_order).includes(:purchase_order, :mes_supplier)
                     .where(account_id: @account.id)
                     .where(mes_purchase_orders: { approval_status: Mes::MaterialPriceResolver::APPROVED_PO })
                     .where.not(mes_purchase_orders: { status: Mes::MaterialPriceResolver::VOID_PO_STATUS })
                     .where('mes_purchase_items.rate_micros > 0')
                     .where(material_or_product(material_ids, product_ids))
                     .order('mes_purchase_orders.created_at DESC')
  end

  def material_or_product(material_ids, product_ids)
    clauses = []
    clauses << Mes::PurchaseItem.where(mes_material_id: material_ids) if material_ids.any?
    clauses << Mes::PurchaseItem.where(crm_product_id: product_ids) if product_ids.any?
    clauses.reduce { |a, b| a.or(b) }.where_clause.ast
  end
end
