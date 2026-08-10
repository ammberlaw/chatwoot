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
      daily: daily(records)
    }
  end

  # 今日速览：当天各店售出数据 + 汇总；含未录入的活跃店铺（提示老板哪些还没报数）。
  def today
    date = Time.zone.today
    records = scope_visible(Current.account.tiktok_daily_sales_records)
              .where(sale_date: date).includes(shop: :department).to_a
    shops = visible_active_shops
    render json: {
      date: date,
      currency: 'CNY',
      summary: summary(records),
      shops: shops.map { |shop| shop_today(shop, records) },
      recorded_shops: records.map(&:shop_id).uniq.size,
      total_shops: shops.size
    }
  end

  private

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

  # 支持按团队(team_id)筛选：限定该团队名下店铺的记录。
  def month_scope
    start_date = Date.strptime(month_str, '%Y-%m')
    scope = scope_visible(Current.account.tiktok_daily_sales_records).where(sale_date: start_date..start_date.end_of_month)
    return scope if params[:team_id].blank?

    shop_ids = Current.account.tiktok_shops.where(department_id: params[:team_id]).pluck(:id)
    scope.where(shop_id: shop_ids)
  rescue ArgumentError
    Current.account.tiktok_daily_sales_records.none
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
