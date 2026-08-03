# 工作月报数据：给定账号 + 某成员 + 报告月份，按该成员的查看权限范围算上月经营数据。
# 口径复用「我的目标 / 看板」：成交金额取未取消订单的 order_amount_micros，
# 新建客户按 created_at，年度目标/累计取当年。范围由 Crm::AccessScope 收口
# （管理员全公司 / 主管团队 / 业务员本人），与页面看板一致。
# 返回 JSON 安全的纯值 hash（供 deliver_later 序列化），金额单位 micros。
class Crm::MonthlyReportService
  def initialize(account, account_user, report_month)
    @account = account
    @account_user = account_user
    @report_month = report_month.beginning_of_month
    @scope = Crm::AccessScope.new(account, account_user)
    @owner_ids = @scope.visible_owner_ids
  end

  def call
    this_amount = deal_amount(month_range(@report_month))
    prev_amount = deal_amount(month_range(@report_month.prev_month))
    this_new = new_customers(month_range(@report_month))
    prev_new = new_customers(month_range(@report_month.prev_month))
    champ = champion

    {
      scope_label: scope_label,
      amount_micros: this_amount,
      amount_mom_pct: mom_pct(this_amount, prev_amount),
      new_customers: this_new,
      customers_mom_pct: mom_pct(this_new, prev_new),
      year_target_micros: year_target,
      ytd_amount_micros: deal_amount(ytd_range),
      champion_name: champ&.first,
      champion_amount_micros: champ&.last
    }
  end

  private

  def month_range(date)
    date.beginning_of_month.beginning_of_day...date.next_month.beginning_of_month.beginning_of_day
  end

  # 年初到报告月末，用于「累计完成」。
  def ytd_range
    @report_month.beginning_of_year.beginning_of_day...@report_month.next_month.beginning_of_month.beginning_of_day
  end

  def apply_scope(relation, column)
    @owner_ids == :all ? relation : relation.where(column => @owner_ids)
  end

  def deal_amount(range)
    apply_scope(@account.crm_sales_orders.dealt, :owner_id)
      .where(order_date: range).sum(:order_amount_micros)
  end

  def new_customers(range)
    apply_scope(@account.crm_customers, :account_owner_id)
      .where(created_at: range).count
  end

  def year_target
    apply_scope(@account.crm_sales_targets, :owner_id)
      .where(target_month: @report_month.beginning_of_year...@report_month.next_year.beginning_of_year)
      .sum(:target_amount_micros)
  end

  # 报告月成交额最高的负责人（仅团队/全公司范围有意义，单人范围返回 nil）。
  def champion
    return nil if @owner_ids != :all && Array(@owner_ids).size <= 1

    top = apply_scope(@account.crm_sales_orders.dealt, :owner_id)
          .where(order_date: month_range(@report_month))
          .group(:owner_id).sum(:order_amount_micros)
          .max_by { |_, amount| amount }
    return nil if top.nil? || top.last.to_i <= 0

    name = @account.users.find_by(id: top.first)&.name
    name ? [name, top.last.to_i] : nil
  end

  # 环比百分比（保留两位）；上月为 0 时无意义返回 nil（模板显示「新增」）。
  def mom_pct(current, previous)
    return nil if previous.to_i <= 0

    (((current - previous).to_f / previous) * 100).round(2)
  end

  def scope_label
    return '全公司' if @scope.all_access?
    return '本团队' if @account_user&.crm_manager?

    '本人'
  end
end
