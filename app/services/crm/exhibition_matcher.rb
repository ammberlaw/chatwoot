# 展会潜客匹配（v1 按「国家/地区」口径）：
# high = 客户贸易国 命中展会所在国；mid = 客户贸易地区 命中展会所在地区；low = 其它。
# 传入的 customers 应已按当前用户可见范围收口（控制器用 visible_customers），本服务只管排序打级。
class Crm::ExhibitionMatcher
  RANK = { 'high' => 0, 'mid' => 1, 'low' => 2 }.freeze

  def initialize(exhibition, customers)
    @exhibition = exhibition
    @customers = customers
  end

  # 候选名单：排除已在邀约名单里的客户；默认只给 high/mid（相关买家），include_low 才带全部。
  def candidates(include_low: false, limit: 300)
    scope = @customers.where(is_in_public_pool: false)
                      .where.not(id: @exhibition.invites.select(:crm_customer_id))

    high = self.class.cond(:trade_country, @exhibition.country)
    mid = self.class.cond(:trade_region, @exhibition.region)
    level_sql = "CASE WHEN #{high} THEN 'high' WHEN #{mid} THEN 'mid' ELSE 'low' END"

    scope = scope.where("#{high} OR #{mid}") unless include_low

    scope.select("crm_customers.*, (#{level_sql}) AS match_level")
         .order(Arel.sql("CASE WHEN #{high} THEN 0 WHEN #{mid} THEN 1 ELSE 2 END"))
         .order(Arel.sql('COALESCE(crm_customers.deal_total_amount_micros, 0) DESC'))
         .limit(limit)
  end

  # 单个客户对某展会的匹配级别（加入名单时定级用）。
  def self.level_for(exhibition, customer)
    return 'high' if match?(customer.trade_country, exhibition.country)
    return 'mid' if match?(customer.trade_region, exhibition.region)

    'low'
  end

  # 列 LIKE 展会字段的 SQL 片段；字段为空则恒 FALSE。
  def self.cond(column, value)
    v = value.to_s.strip.downcase
    return 'FALSE' if v.blank?

    "LOWER(crm_customers.#{column}) LIKE #{ActiveRecord::Base.connection.quote("%#{v}%")}"
  end

  def self.match?(customer_value, exhibition_value)
    a = customer_value.to_s.strip.downcase
    b = exhibition_value.to_s.strip.downcase
    a.present? && b.present? && a.include?(b)
  end
end
