# 跨产品线搜型号：业务员知道客户要哪个型号，未必知道它归在哪条产品线。
# 只搜文本列（型号/名称/参数）——价格列搜数字没意义。
class Crm::PriceListSearch
  def initialize(lists:, query:, limit: 60)
    @lists = lists
    @query = query.to_s.downcase
    @limit = limit
  end

  def call
    rows = []
    @lists.each do |list|
      text_idx = list.column_defs.each_index.reject { |i| list.column_defs[i]['type'] == 'price' }
      list.items.ordered.each do |item|
        next unless hit?(item, text_idx)

        rows << row(list, item)
        return rows if rows.size >= @limit
      end
    end
    rows
  end

  private

  def hit?(item, text_idx)
    text_idx.any? { |i| item.values[i].to_s.downcase.include?(@query) }
  end

  def row(list, item)
    { product_line: list.product_line, list_id: list.id, status: list.status,
      effective_on: list.effective_on, currency: list.currency,
      columns: list.column_defs, values: item.values,
      image_url: item.image.attached? ? Rails.application.routes.url_helpers.rails_blob_path(item.image, only_path: true) : nil }
  end
end
