# 库存单审核通过即自动转成现货出库单。
#
# 为什么要自动：转单一直是审核之后的一个独立人工动作，没人去点就断在那儿——
# 生产上 62 张销售订单标着「生产中」、MES 里既没有生产单也没有出库单，跨度一年多
# （2026-10-21 排查）。审核通过就是「这单可以往下走」的决定，转单跟着它走最自然。
#
# 只管库存单。定制单要填规格、选接单方式，由业务到 MES 建单（那边能关联回这张销售订单）。
#
# 出库单仍然进**财务审核**（查款收齐没有，见 Mes::Shipment#submit_for_approval! 的注释），
# 不是主管审核——主管那道已经在销售订单上了。自动转单省掉的是「点一下转单」，
# 不是收款那道闸。
class Crm::StockOrderAutoConvert
  def initialize(sales_order, actor)
    @order = sales_order
    @actor = actor
    @account = sales_order.account
  end

  # 返回一句给人看的说明（成功/为什么没转），不走自动转时返回 nil。
  def call
    return nil unless @order.order_kind == 'STOCK'
    return '这张单已经有出库单了，没有重复转' if existing_shipment

    rows = convertible_rows
    return rows if rows.is_a?(String) # 挡不住的原因，原样带回

    shipment = build_and_submit(rows)
    "已自动生成现货出库单 #{shipment.shipment_no}，等财务审核收款"
  rescue StandardError => e
    # 转不动不该让审核失败：审核是人刚做出的决定。原因带回去让人工转一次。
    Rails.logger.warn("[Crm::StockOrderAutoConvert] #{@order.order_no}: #{e.message}")
    "审核已通过，但自动转出库单没成功（#{e.message}），请在订单上手工点一次转单"
  end

  private

  def existing_shipment
    @account.mes_shipments.where(crm_sales_order_id: @order.id).where.not(status: 'CANCELLED').first
  end

  # 明细行 → 成品档案。匹配不上的行不能猜着转（转错货比没转更难收场），
  # 整单退回人工，并把对不上的行名点出来。
  def convertible_rows
    rows = Crm::ConvertPreview.new(@order).rows.select { |row| row[:quantity].to_d.positive? }
    return '订单没有可转的明细行（数量都是 0）' if rows.empty?

    unmatched = rows.reject { |row| row[:crm_product_id].present? }
    return unmatched_note(unmatched) if unmatched.any?

    rows
  end

  def unmatched_note(unmatched)
    names = unmatched.map { |row| row[:name].presence || "第 #{row[:row]} 行" }.first(3).join('、')
    more = unmatched.size > 3 ? " 等 #{unmatched.size} 行" : ''
    "审核已通过，但有明细对不上成品档案（#{names}#{more}），请在订单上手工点一次转单选中产品"
  end

  def build_and_submit(rows)
    warehouse = finished_warehouse
    raise StandardError, '账套里没有成品仓' if warehouse.nil?

    shipment = @account.mes_shipments.new(
      kind: 'STOCK', crm_sales_order: @order, crm_customer_id: @order.crm_customer_id,
      warehouse_id: warehouse.id, owner_id: @order.owner_id || @actor&.id,
      remark: "由销售订单 #{@order.order_no} 审核通过后自动转入",
      shipment_items_attributes: rows.map { |row| item_attrs(row) }
    )
    # 产线留空的单，切到具体产线的人就看不见了（Mes::Shipment 不强制这列，
    # 但列表按产线过滤）。销售订单上没有产线，从转出来的成品档案上取第一个非空的。
    shipment.fallback_product_line = product_line_for(rows)
    ActiveRecord::Base.transaction do
      shipment.save!
      shipment.submit_for_approval!(@actor)
    end
    shipment
  end

  def item_attrs(row)
    { crm_product_id: row[:crm_product_id], qty: row[:quantity], unit: row[:product_unit].presence }
  end

  def product_line_for(rows)
    @account.crm_products.where(id: rows.pluck(:crm_product_id))
            .where.not(product_line: nil).pick(:product_line)
  end

  # 转单弹窗默认也是挑成品仓（kind=FINISHED），这里跟它一致。
  def finished_warehouse
    @account.mes_warehouses.where(kind: 'FINISHED').order(:id).first
  end
end
