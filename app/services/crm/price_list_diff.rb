# 两版核价表对比：涨了 / 降了 / 新增 / 下架。主管发布新版前自查，业务员也能看「这次调了哪些」。
#
# 按「型号」认行——同一张表里名称常常重复（同一款不同触摸类型），型号才是唯一的。
# 没有型号列的表（如水牌机按配置列价）退回用所有文本列拼起来当键。
class Crm::PriceListDiff
  KEY_LABELS = %w[型号 整机名称 名称].freeze

  def initialize(current:, previous:)
    @current = current
    @previous = previous
  end

  def call
    now = index_rows(@current)
    before = index_rows(@previous)
    {
      current: version_info(@current),
      previous: version_info(@previous),
      added: (now.keys - before.keys).map { |k| { key: k, values: now[k][:values] } },
      removed: (before.keys - now.keys).map { |k| { key: k, values: before[k][:values] } },
      changed: changed_rows(now, before)
    }
  end

  private

  def version_info(list)
    { id: list.id, effective_on: list.effective_on, status: list.status,
      currency: list.currency, columns: list.column_defs }
  end

  # { 型号 => { values:, prices: { 档位 => 数值 } } }
  def index_rows(list)
    cols = list.column_defs
    key_idx = key_index(cols)
    list.items.ordered.to_h do |item|
      key = key_idx ? item.values[key_idx].to_s.strip : text_key(cols, item)
      [key.presence || item.id.to_s, { values: item.values, prices: price_map(cols, item) }]
    end
  end

  def key_index(cols)
    KEY_LABELS.each do |label|
      idx = cols.index { |c| c['label'] == label }
      return idx if idx
    end
    nil
  end

  def text_key(cols, item)
    cols.each_index.reject { |i| cols[i]['type'] == 'price' }.map { |i| item.values[i] }.join('｜')
  end

  def price_map(cols, item)
    cols.each_with_index.filter_map do |c, i|
      next unless c['type'] == 'price'

      value = Float(item.values[i].to_s.delete('$¥, '), exception: false)
      [c['label'], value] if value
    end.to_h
  end

  # 同一个型号、任一档位价格变了就算改动；给出每档的旧值/新值/涨跌幅。
  def changed_rows(now, before)
    (now.keys & before.keys).filter_map do |key|
      deltas = price_deltas(before[key][:prices], now[key][:prices])
      next if deltas.empty?

      { key: key, values: now[key][:values], deltas: deltas }
    end
  end

  def price_deltas(old_prices, new_prices)
    (old_prices.keys | new_prices.keys).filter_map do |label|
      was = old_prices[label]
      now = new_prices[label]
      next if was == now || was.nil? || now.nil?

      { label: label, was: was.round(2), now: now.round(2),
        percent: was.zero? ? nil : (((now - was) / was) * 100).round(1) }
    end
  end
end
