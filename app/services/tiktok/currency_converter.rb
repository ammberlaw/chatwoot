# 实时汇率换算（外币→人民币）。用于 TikTok 日报销售额录入时的 RMB 快照。
# 免费接口 open.er-api.com（无需 key），整表缓存 12h 降调用；接口不可用/超时时回落到兜底汇率，
# 保证录入与看板不因外网不通而挂（生产在腾讯云，外网连通性以部署验证为准）。
class Tiktok::CurrencyConverter
  SUPPORTED = %w[USD EUR PHP CNY].freeze

  # 兜底汇率：1 单位外币 = ? 人民币。量级正确即可（2026 年上半年参考值），仅接口不可用时启用。
  FALLBACK_TO_CNY = {
    'USD' => 7.15,
    'EUR' => 7.75,
    'PHP' => 0.125,
    'CNY' => 1.0
  }.freeze

  CACHE_KEY = 'tiktok:fx_rates_to_cny'.freeze
  CACHE_TTL = 12.hours
  API_URL = 'https://open.er-api.com/v6/latest/CNY'.freeze

  # 1 单位 currency = ? 人民币。
  def self.rate_to_cny(currency)
    code = currency.to_s.upcase
    return 1.0 if code == 'CNY'

    table[code] || FALLBACK_TO_CNY[code] || 1.0
  end

  # {USD=>x, EUR=>y, PHP=>z, CNY=>1.0}，缓存 12h；异常回落兜底。
  def self.table
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { fetch_table }
  rescue StandardError
    FALLBACK_TO_CNY
  end

  # 接口返回「1 CNY = ? 外币」，取倒数得「1 外币 = ? CNY」。任一币种缺失/异常回落兜底。
  def self.fetch_table
    response = HTTParty.get(API_URL, timeout: 5)
    rates = response.parsed_response&.dig('rates')
    return FALLBACK_TO_CNY if rates.blank?

    SUPPORTED.index_with do |code|
      next 1.0 if code == 'CNY'

      per_cny = rates[code].to_f
      per_cny.positive? ? (1.0 / per_cny).round(6) : FALLBACK_TO_CNY[code]
    end
  rescue StandardError
    FALLBACK_TO_CNY
  end
end
