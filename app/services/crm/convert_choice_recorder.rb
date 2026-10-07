# 转单弹窗里人工点中的「这行明细 = 这个产品」，落回去两个地方。
#
# 销售订单明细是自由文本（PI 识别填的），下游要产品档案 ID 才能扣库存/带 BOM，
# 所以转单时要人工点一次。原先这一次点击**点完就扔**：既不写回明细、也不进
# 别名记忆，于是 744 行明细里 0 行带 crm_product_id、别名表 0 条，
# 同一个产品名下次转单还要从上千条产品档案里重新搜一遍。
#
# 现在写两处：
#   明细的 crm_product_id —— 这张订单再转（补转漏的行、改数量重转）直接带出来；
#   Crm::ProductAlias     —— 换一张订单、同样的客户叫法，Crm::LineItemProductMatcher 自动命中。
#
# 记录失败一律不影响转单：单据已经建好了，不该为了记忆把成功的事务回滚。
class Crm::ConvertChoiceRecorder
  def initialize(sales_order)
    @order = sales_order
    @account = sales_order.account
  end

  # rows: [{ row: 1-based 明细行号, crm_product_id: 1 }, ...]，row 缺失（弹窗里手工加的行）只喂记忆。
  def call(rows)
    pairs = Array(rows).filter_map do |row|
      product_id = row[:crm_product_id].presence&.to_i
      next if product_id.blank?

      { index: row[:row].presence&.to_i, product_id: product_id }
    end
    return if pairs.empty?

    write_back(pairs)
  rescue StandardError => e
    Rails.logger.warn("[转单记忆] 订单 #{@order.order_no} 回写失败：#{e.class} #{e.message}")
  end

  private

  def write_back(pairs)
    items = Array(@order.line_items).map { |i| i.is_a?(Hash) ? i.dup : i }
    touched = false

    pairs.each do |pair|
      item = line_item_at(items, pair[:index])
      next if item.nil?

      remember(item['name'], pair[:product_id])
      next if item['crm_product_id'].to_i == pair[:product_id]

      item['crm_product_id'] = pair[:product_id]
      touched = true
    end

    # update_columns：转单不是编辑订单，不该写审计、不该跑成交汇总回调、
    # 更不该因为订单本身的校验（必传附件等）让回写失败。
    @order.update_columns(line_items: items, updated_at: Time.current) if touched
  end

  # 行号是 1 起的。不校验的话 row=0 会被 items[-1] 解释成最后一行，
  # 把产品关联写到完全无关的明细上。
  def line_item_at(items, index)
    return nil unless index.to_i.positive?

    item = items[index - 1]
    item.is_a?(Hash) ? item : nil
  end

  def remember(text, product_id)
    Crm::ProductAlias.remember!(account: @account, text: text, product_id: product_id)
  end
end
