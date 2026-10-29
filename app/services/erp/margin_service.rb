# 毛利：订单收入 - 归集成本，实时算不落库（ERP_SPEC §4.2）。
#
# 收入口径：优先取应收台账金额（财务确认过的），没建台账就退回销售订单金额＋运费。
# 成本口径：erp_order_costs 归集行的本位币合计。
# 只在 ERP 内可见——销售端接口一律不得输出这些数（§13-2）。
class Erp::MarginService
  def initialize(account)
    @account = account
  end

  # 报表入口：明细最多回传 limit 行（多出的打 truncated 标记），
  # **表头合计与维度汇总永远按全量算**——按截断行数出的合计是错数还看不出来错。
  def report(from: nil, to: nil, group_by: nil, limit: 200, q: nil, owner_id: nil)
    rows = by_order(from: from, to: to, limit: nil, q: q, owner_id: owner_id)
    {
      rows: rows.first(limit), truncated: rows.size > limit, total_count: rows.size,
      totals: totals_of(rows),
      summary: group_by ? summarize(rows, group_by) : []
    }
  end

  # 订单维度毛利表。limit: nil＝全量（汇总口径用）。
  def by_order(from: nil, to: nil, limit: 200, q: nil, owner_id: nil)
    scope = order_scope(from, to, q: q, owner_id: owner_id)
    scope = scope.limit(limit) if limit
    orders = scope.to_a
    receivables = @account.erp_receivables.where(crm_sales_order_id: orders.map(&:id)).index_by(&:crm_sales_order_id)
    costs = cost_totals(orders.map(&:id))
    orders.map { |order| row_for(order, receivables[order.id], costs[order.id].to_i) }
  end

  # 汇总维度（业务员 / 客户），拿全量订单行再聚合。
  def summary_by(dimension, from: nil, to: nil, q: nil, owner_id: nil)
    summarize(by_order(from: from, to: to, limit: nil, q: q, owner_id: owner_id), dimension)
  end

  private

  # 按 id 分组、名字只做展示——按名字分组会把同名客户/同名业务员并成一行（迁移数据里同名客户真实存在）。
  def summarize(rows, dimension)
    grouped = rows.group_by do |row|
      dimension == 'customer' ? [row[:customer_id], row[:customer_name]] : [row[:owner_id], row[:owner_name]]
    end
    grouped.map { |(_id, name), group| aggregate(name, group) }.sort_by { |row| -row[:revenue_micros] }
  end

  def totals_of(rows)
    {
      revenue_micros: rows.sum { |row| row[:revenue_micros] },
      cost_micros: rows.sum { |row| row[:cost_micros] },
      margin_micros: rows.sum { |row| row[:margin_micros] }
    }
  end

  def order_scope(from, to, q: nil, owner_id: nil)
    scope = @account.crm_sales_orders.includes(:crm_customer, :owner).order(order_date: :desc)
    scope = scope.where(order_date: from..) if from.present?
    scope = scope.where(order_date: ..to) if to.present?
    scope = scope.where(owner_id: owner_id) if owner_id.present?
    # 搜索：订单号 / 订单名 / 客户名。库里几百张单，不给搜只能一页页翻。
    # 客户名要 join 才搜得到——left_joins 而不是 joins，没挂客户的单不能因此被筛掉。
    if q.to_s.strip.present?
      term = "%#{q.to_s.strip}%"
      scope = scope.left_joins(:crm_customer)
                   .where('crm_sales_orders.order_no ILIKE :t OR crm_sales_orders.name ILIKE :t ' \
                          'OR crm_customers.name ILIKE :t', t: term)
    end
    scope
  end

  def cost_totals(order_ids)
    @account.erp_order_costs.where(crm_sales_order_id: order_ids)
            .group(:crm_sales_order_id)
            .sum(Arel.sql('ROUND(amount_micros * COALESCE(exchange_rate, 1))'))
  end

  def row_for(order, receivable, cost_micros)
    revenue = revenue_of(order, receivable)
    margin = revenue - cost_micros
    order_identity(order).merge(
      revenue_micros: revenue, cost_micros: cost_micros, margin_micros: margin,
      margin_rate: rate_of(margin, revenue), receivable_no: receivable&.receivable_no
    )
  end

  def order_identity(order)
    {
      order_id: order.id, order_no: order.order_no, order_name: order.name,
      order_date: order.order_date&.to_date,
      customer_id: order.crm_customer_id,
      customer_name: order.crm_customer&.name,
      owner_id: order.owner_id,
      # 中文名优先。crm_name（CRM 英文名）是给对客场景用的——CRM 界面和外发邮件显英文，
      # 核心系统显中文。成本毛利是财务板块、只给自己人看，摆英文名反而对不上人。
      owner_name: order.owner&.finance_display_name
    }
  end

  def rate_of(margin, revenue)
    revenue.positive? ? (margin * 100.0 / revenue).round(2) : nil
  end

  # 收入折本位币：台账/订单都可能是外币，一律按其汇率折算。
  #
  # 没建台账时取 gross_sales_micros（订单金额 + 运费），不是订单金额原值：
  # 成本侧归集得了「运费」（付货代的钱），收入侧漏掉向客户收的运费，
  # 毛利就凭空少一笔。建过台账的走台账金额，那个数本身已含运费。
  def revenue_of(order, receivable)
    if receivable
      (receivable.total_amount_micros * receivable.exchange_rate).round
    else
      (order.gross_sales_micros * (order.exchange_rate.presence || 1)).round
    end
  end

  def aggregate(name, group)
    revenue = group.sum { |row| row[:revenue_micros] }
    cost = group.sum { |row| row[:cost_micros] }
    {
      name: name.presence || '未指定', order_count: group.size,
      revenue_micros: revenue, cost_micros: cost, margin_micros: revenue - cost,
      margin_rate: rate_of(revenue - cost, revenue)
    }
  end
end
