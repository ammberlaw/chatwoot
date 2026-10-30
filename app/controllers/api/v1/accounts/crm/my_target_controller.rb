# 我的目标：返回当前业务员某年 12 个月的「基础目标 + 实绩」原始数据。
# 结转/有效目标/达成率由前端按季度规则实时计算（未完成滚下月、每季度清零）。
# 编辑基础目标复用 crm/sales_targets 的 create/update。
class Api::V1::Accounts::Crm::MyTargetController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    year = (params[:year] || Time.zone.today.year).to_i
    render json: { year: year, months: months_payload(year), baseline: baseline_payload }
  end

  private

  # 本月保本线：做多少销售额，提成刚好覆盖自己的月薪。只给这一个数——
  # 他看自己的工资条本来就知道月薪，但页面上不摆月薪，免得截图外传。
  def baseline_payload
    result = Crm::SalaryBaseline.new(account: Current.account).for_owner(current_user.id)
    { monthly_micros: result.recorded_micros.presence || result.suggested_micros,
      from_salary_table: result.recorded_micros.present?,
      new_hire: result.new_hire?, tenure_months: result.tenure_months }
  end

  def year_range(year)
    Time.zone.local(year, 1, 1)...Time.zone.local(year + 1, 1, 1)
  end

  def month_expr(column)
    Arel.sql("EXTRACT(MONTH FROM #{column})::int")
  end

  def months_payload(year)
    base = base_targets(year)
    amounts = actual_amounts(year)
    counts = actual_counts(year)

    (1..12).map do |m|
      b = base[m] || { id: nil, amount: 0, count: 0 }
      # ⚠️ 金额一律 to_i：SUM(ROUND(...)) 在 PG 是 numeric → Ruby BigDecimal
      # → JSON 里是**字符串** "104500000000.0"，前端逐月 += 会变字符串拼接，
      # 拼两次出现两个小数点就成 NaN（表现为每季度第三个月达成率 NaN%）。
      {
        month: m,
        base_id: b[:id],
        base_amount_micros: b[:amount].to_i,
        base_count: b[:count].to_i,
        actual_amount_micros: amounts[m].to_i,
        actual_count: counts[m].to_i
      }
    end
  end

  # 当前用户当年的基础目标，按月合并（同月多条以第一条 id 作编辑锚）
  def base_targets(year)
    rows = Current.account.crm_sales_targets
                  .owned_by(current_user.id)
                  .where(target_month: year_range(year))
                  .order(:target_month, :id)
                  .pluck(month_expr('target_month'), :id, :target_amount_micros, :target_order_count)
    rows.each_with_object({}) do |(month, id, amount, count), acc|
      acc[month] ||= { id: id, amount: 0, count: 0 }
      acc[month][:amount] += amount || 0
      acc[month][:count] += count || 0
    end
  end

  def actual_amounts(year)
    Current.account.crm_sales_orders.dealt.owned_by(current_user.id)
           .where(order_date: year_range(year))
           .group(month_expr('order_date')).sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL))
  end

  # 新成交客户：负责人=当前用户、首次成交日期落在该月的客户（按客户去重，first_deal_at 每客户唯一）
  def actual_counts(year)
    Current.account.crm_customers.owned_by(current_user.id)
           .where(first_deal_at: year_range(year))
           .group(month_expr('first_deal_at')).count
  end

  def check_authorization
    authorize(Crm::SalesTarget)
  end
end
