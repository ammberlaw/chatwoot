# 生产任务单选定商品编码后，把编码回填到它挂的那张销售订单明细上。
#
# 为什么要回填：编码在生产这头是刚需（成品入库、SN、成本都要它），销售订单明细却是
# PI 识别出来的自由文本。生产上 43 张在产单里 16 张没挂档案，它们的销售订单明细
# **一行带编码的都没有**——同一个产品被录两遍、两头都对不上档案（2026-10-09）。
# 生产这头选一次，销售那头跟着有，后面开票/出库就不用再点一次。
#
# 对应哪一行：生产订单只记了挂哪张销售订单，没记来源行号，所以
#   · 明细只有一行     → 就是它，无歧义
#   · 多行             → 按品名匹配（精确 → 去空格/大小写 → 互相包含），命中**唯一**一行才写
#   · 匹配不到或多行同时命中 → 不写。猜错了会把编码写到无关明细上，比不写更糟。
# 写回与别名记忆都走 Crm::ConvertChoiceRecorder（和转单时人工点选同一条路）。
class Mes::SalesOrderProductBackfill
  def initialize(production_order)
    @order = production_order
  end

  def call
    return if @order.crm_product_id.blank?

    sales_order = @order.crm_sales_order
    return if sales_order.nil?

    index = match_index(Array(sales_order.line_items))
    return if index.nil?

    Crm::ConvertChoiceRecorder.new(sales_order)
                              .call([{ row: index, crm_product_id: @order.crm_product_id }])
  end

  private

  # 返回 1 起的明细行号；定不下来就返回 nil。
  def match_index(items)
    rows = items.each_with_index.select { |item, _| item.is_a?(Hash) }
    return nil if rows.empty?
    return 1 if rows.size == 1

    hits = rows.select { |item, _| same_product?(item['name']) }
    hits.size == 1 ? hits.first.last + 1 : nil
  end

  def same_product?(name)
    a = normalize(name)
    b = normalize(@order.product_name)
    return false if a.blank? || b.blank?

    a == b || a.include?(b) || b.include?(a)
  end

  def normalize(text)
    text.to_s.downcase.gsub(/\s+/, '')
  end
end
