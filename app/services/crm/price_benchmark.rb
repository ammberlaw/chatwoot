# 销售单价和「上一次卖多少」比，给审核人一句提示。
#
# 用户 2026-10-29 提：审业务员的销售订单、财务审出库单时，想一眼看出这个价
# 跟最近一次比是高了还是低了、异不异常。
#
# ⚠️ 按**品名**比，不是按商品编码。生产实查 841 条订单明细：填了编码的 **0 条**，
# 填了品名的 841 条——业务员录的是型号名（K717/Q75X），编码是转单那步才补的。
# 按编码比一条都比不出来；按品名有 86 个型号攒够了历史。
#
# 口径（用户定）：
#   · 同客户优先 —— 同一个客户上次买 30 这次卖 20 才是真异常；
#     没跟这家做过才回退到全公司最近一次，并在提示里注明是哪种比法
#     （不同市场价差本来就大：迪拜/欧规/1688 混在一起比会天天误报）
#   · ±10% 提醒、±30% 标红
#
# 只比**同币种**：USD 的 25 和 CNY 的 180 不是一回事。
class Crm::PriceBenchmark
  WARN_RATIO = 0.10
  ALERT_RATIO = 0.30
  # 翻多少单去找上一次。全表扫没必要，历史久远的价也没参考意义。
  LOOKBACK = 300

  Result = Struct.new(:last_price, :diff_ratio, :level, :scope_label, :order_no, :order_date,
                      keyword_init: true)

  def initialize(account)
    @account = account
  end

  # rows: [{ name:, unit_price: }]，返回 { 品名 => Result }
  def for_order(order)
    rows = order.line_item_rows
    names = rows.filter_map { |r| normalize(r[:name]) }.uniq
    return {} if names.empty?

    history = history_for(names, order.order_currency, exclude_order_id: order.id)
    rows.each_with_object({}) do |row, out|
      result = result_for(row, history, order.crm_customer_id)
      out[row[:name]] = result if result
    end
  end

  private

  def result_for(row, history, customer_id)
    key = normalize(row[:name])
    return nil if key.blank? || row[:unit_price].to_d <= 0

    hit = pick(history[key], customer_id)
    hit && compare(row[:unit_price].to_d, hit)
  end

  def normalize(value) = value.to_s.strip.upcase.presence

  def compare(price, hit)
    last = hit[:price]
    ratio = ((price - last) / last).to_f
    Result.new(
      last_price: last.to_f, diff_ratio: ratio.round(4),
      level: level_of(ratio), scope_label: hit[:same_customer] ? '该客户上次' : '最近一次',
      order_no: hit[:order_no], order_date: hit[:order_date]
    )
  end

  def level_of(ratio)
    abs = ratio.abs
    return 'alert' if abs >= ALERT_RATIO
    return 'warn' if abs >= WARN_RATIO

    'normal'
  end

  # 同客户的优先；都没有就拿全公司最近那条。
  def pick(entries, customer_id)
    return nil if entries.blank?

    entries.find { |e| e[:customer_id] == customer_id }&.merge(same_customer: true) ||
      entries.first&.merge(same_customer: false)
  end

  # { 品名 => [按时间倒序的成交记录] }。同币种、已审核、未删除的单才作数——
  # 待审核的单价还可能被驳回改掉，拿它当基准等于用没定的数去判别人。
  def history_for(names, currency, exclude_order_id:)
    rows = recent_orders(currency).reject { |row| row.first == exclude_order_id }
    tally = Hash.new { |h, k| h[k] = [] }
    rows.each do |_id, order_no, date, customer_id, items|
      collect(tally, names, items, { order_no: order_no, order_date: date, customer_id: customer_id })
    end
    tally
  end

  # 按币种缓存：出库审核页一屏好几张待审单，每张都重查 300 条是白跑。
  # 一个实例＝一次请求，缓存只活这一次。
  def recent_orders(currency)
    code = currency.presence || 'CNY'
    @recent_orders ||= {}
    @recent_orders[code] ||= @account.crm_sales_orders
                                     .where(deleted_at: nil, approval_status: 'APPROVED')
                                     .where(order_currency: code)
                                     .order(order_date: :desc, id: :desc)
                                     .limit(LOOKBACK)
                                     .pluck(:id, :order_no, :order_date, :crm_customer_id, :line_items)
  end

  # meta = { order_no:, order_date:, customer_id: }，这张单上所有命中的行共用同一份。
  def collect(tally, names, items, meta)
    Array(items).each do |item|
      next unless item.is_a?(Hash)

      key = normalize(item['name'])
      price = item['unit_price'].to_d
      next if key.blank? || names.exclude?(key) || price <= 0

      tally[key] << meta.merge(price: price)
    end
  end
end
