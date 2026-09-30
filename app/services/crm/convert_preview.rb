# 转单弹窗的明细预览：这张销售订单的每行明细，对应哪个产品档案。
#
# 口径优先级：
#   1. 明细上已经存好的 crm_product_id —— 业务员建单时选过的，最权威，不要再猜
#   2. Crm::LineItemProductMatcher —— 记忆 > 编码精确 > 名称精确 > 编码/名称/规格模糊
#
# 原来这里是控制器里一段只按产品名精确匹配的私有方法，既无视已存的关联、
# 命中多条就放弃，实测 199 行明细只带出 22 行。现在统一走匹配服务，
# 拿不准就把候选带回去让人一次点中。
class Crm::ConvertPreview
  def initialize(sales_order)
    @order = sales_order
    @account = sales_order.account
  end

  def rows
    items.each_with_index.map { |item, index| row(item, index) }
  end

  private

  def items
    @items ||= Array(@order.line_items).select { |i| i.is_a?(Hash) }
  end

  # 已关联的一次性取出来，避免逐行查库。
  def linked
    @linked ||= begin
      ids = items.filter_map { |i| i['crm_product_id'].presence&.to_i }.uniq
      ids.empty? ? {} : @account.crm_products.where(id: ids).index_by(&:id)
    end
  end

  # 只有没存关联的行才需要匹配——已选过的不该被猜测覆盖。
  def matches
    @matches ||= begin
      texts = items.reject { |i| i['crm_product_id'].present? }.map { |i| i['name'].to_s }
      texts.empty? ? {} : Crm::LineItemProductMatcher.new(@account).match_all(texts)
    end
  end

  def row(item, index)
    name = item['name'].to_s
    linked_product = linked[item['crm_product_id'].to_i]
    row = if linked_product
            base(item, index, name).merge(product_fields(linked_product)).merge(source: 'linked')
          else
            hit = matches[name] || {}
            base(item, index, name)
              .merge(product_fields(hit[:product]))
              .merge(source: hit[:source], fee: hit[:fee], candidates: candidates(hit[:candidates]))
          end
    row.merge(converted_order_no: converted[row[:crm_product_id]])
  end

  # 已经转过生产订单的行：弹窗要当场标出来，让人只勾没转的那几行。
  # 后端提交时也会按「销售订单+产品」跳过已转的，这里只是提前告知。
  def converted
    @converted ||= @account.mes_production_orders
                           .where(crm_sales_order_id: @order.id).where.not(status: 'CANCELLED')
                           .pluck(:crm_product_id, :order_no).to_h
  end

  def base(item, index, name)
    { row: index + 1, name: name, spec: item['spec'].presence,
      quantity: item['quantity'], unit_price: item['unit_price'],
      fee: false, candidates: [] }
  end

  def product_fields(product)
    {
      crm_product_id: product&.id,
      product_name: product&.name,
      product_sku: product&.sku,
      product_spec: product&.specification,
      product_unit: product&.unit
    }
  end

  def candidates(list)
    Array(list).map do |p|
      { id: p.id, name: p.name, sku: p.sku, specification: p.specification, unit: p.unit }
    end
  end
end
