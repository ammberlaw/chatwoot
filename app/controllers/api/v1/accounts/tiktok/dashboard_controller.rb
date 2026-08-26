# TikTok 数据看板：按 month(YYYY-MM，缺省当月) 汇总 KPI + 分团队 + 每日趋势。
# 金额一律用录入时的 RMB 快照（sales_amount_cny）汇总，口径稳定。
class Api::V1::Accounts::Tiktok::DashboardController < Api::V1::Accounts::Tiktok::BaseController
  def show
    records = month_scope.includes(shop: :department).order(:sale_date).to_a
    render json: {
      month: month_str,
      currency: 'CNY',
      summary: summary(records),
      by_team: by_team(records),
      by_source: by_source(records),
      daily: daily(records),
      teams: visible_teams
    }
  end

  # 今日速览：展示「最近有数据的一天」各店售出数据 + 汇总（TK 日报常报前一日，
  # 严格取当天多为空，故回退到最新已录入的一天；无任何数据时才用今天）。
  def today
    visible = scope_visible(Current.account.tiktok_daily_sales_records)
    date = visible.maximum(:sale_date) || Time.zone.today
    records = visible.where(sale_date: date).includes(shop: :department).to_a
    prev_records = visible.where(sale_date: date - 1).to_a
    shops = visible_active_shops
    render json: {
      date: date,
      currency: 'CNY',
      summary: summary(records),
      shops: shops.map { |shop| shop_today(shop, records) },
      recorded_shops: records.map(&:shop_id).uniq.size,
      total_shops: shops.size,
      day_compare: { today: day_metrics(records), yesterday: day_metrics(prev_records) }
    }
  end

  private

  # 看板团队筛选下拉：当前成员可见的全部 TK 部门（含未挂店铺的新部门，与 by_team 靠记录聚合不同）。
  def visible_teams
    ids = tiktok_scope.visible_department_ids
    scope = Current.account.tiktok_departments.order(:name)
    scope = scope.where(id: ids) unless ids == :all
    scope.map { |dept| { id: dept.id, name: dept.name } }
  end

  # 当前成员可见的活跃店铺（含所属团队），用于今日速览逐店展示。
  def visible_active_shops
    ids = tiktok_scope.visible_shop_ids
    scope = Current.account.tiktok_shops.active.includes(:department).ordered
    ids == :all ? scope : scope.where(id: ids)
  end

  # 单店今日数据（无记录则各项为 0，标记未录入）。
  def shop_today(shop, records)
    rows = records.select { |r| r.shop_id == shop.id }
    units = rows.sum(&:total_units)
    {
      shop_id: shop.id,
      shop_name: shop.name,
      team_name: shop.department&.name,
      has_data: rows.any?,
      amount_cny: rows.sum { |r| r.sales_amount_cny.to_f }.round(2),
      total_orders: rows.sum(&:total_orders),
      total_units: units,
      shipped_units: rows.sum(&:shipped_units),
      influencer_units: rows.sum(&:influencer_units),
      cancel_rate: rate(rows.sum(&:cancelled_units), units)
    }
  end

  def month_str
    params[:month].presence || Time.zone.today.strftime('%Y-%m')
  end

  # 当前成员可见 + 团队(team_id)筛选后的记录集（不限日期）。
  def visible_team_scope
    scope = scope_visible(Current.account.tiktok_daily_sales_records)
    return scope if params[:team_id].blank?

    shop_ids = Current.account.tiktok_shops.where(department_id: params[:team_id]).pluck(:id)
    scope.where(shop_id: shop_ids)
  end

  def month_scope
    start_date = Date.strptime(month_str, '%Y-%m')
    visible_team_scope.where(sale_date: start_date..start_date.end_of_month)
  rescue ArgumentError
    Current.account.tiktok_daily_sales_records.none
  end

  # 订单来源饼图：本月四类订单来源合计（联盟直播/联盟/商品卡/商家）。
  def by_source(records)
    {
      alliance_live: records.sum(&:alliance_live_orders),
      alliance: records.sum(&:alliance_orders),
      product_card: records.sum(&:product_card_orders),
      merchant: records.sum(&:merchant_orders)
    }
  end

  # 今日 vs 昨日环比口径：销售额(RMB)/订单/台数。
  def day_metrics(rows)
    {
      amount_cny: rows.sum { |r| r.sales_amount_cny.to_f }.round(2),
      total_orders: rows.sum(&:total_orders),
      total_units: rows.sum(&:total_units)
    }
  end

  # KPI 卡：总销售额(RMB) / 总订单 / 总台数 / 签收(实发)台数 / 达人台数 / 加权平均取消率+有效率。
  def summary(records)
    units = records.sum(&:total_units)
    {
      amount_cny: records.sum { |r| r.sales_amount_cny.to_f }.round(2),
      total_orders: records.sum(&:total_orders),
      total_units: units,
      shipped_units: records.sum(&:shipped_units),
      cancelled_units: records.sum(&:cancelled_units),
      influencer_units: records.sum(&:influencer_units),
      cancel_rate: rate(records.sum(&:cancelled_units), units),
      valid_rate: rate(records.sum(&:shipped_units), units)
    }
  end

  # 分团队明细（看板对比表）：按店铺所属 TK 部门聚合；未分配部门归「未分配」。
  def by_team(records)
    records.group_by { |r| r.shop&.department_id }.map do |dept_id, rows|
      units = rows.sum(&:total_units)
      {
        team_id: dept_id,
        team_name: rows.first.shop&.department&.name || '未分配团队',
        shop_count: rows.map(&:shop_id).uniq.size,
        amount_cny: rows.sum { |r| r.sales_amount_cny.to_f }.round(2),
        total_orders: rows.sum(&:total_orders),
        total_units: units,
        shipped_units: rows.sum(&:shipped_units),
        influencer_units: rows.sum(&:influencer_units),
        cancel_rate: rate(rows.sum(&:cancelled_units), units),
        valid_rate: rate(rows.sum(&:shipped_units), units)
      }
    end.sort_by { |r| -r[:amount_cny] }
  end

  # 每日趋势（折线图）：同一天多店合并汇总。
  def daily(records)
    records.group_by(&:sale_date).map do |date, rows|
      {
        date: date,
        amount_cny: rows.sum { |r| r.sales_amount_cny.to_f }.round(2),
        total_orders: rows.sum(&:total_orders),
        total_units: rows.sum(&:total_units)
      }
    end.sort_by { |r| r[:date] }
  end

  def rate(part, whole)
    whole.to_i.zero? ? nil : (part.to_f / whole).round(4)
  end
end
