# 把 IP 解析成中文归属地（城市/国家），供邮件打开追踪展示「打开地点」。
# 优先用本地 MaxMind 库（若已配置 IP_LOOKUP_API_KEY 下载了 DB），否则走免密钥在线接口 ip-api.com。
# 私网/回环 IP 跳过；结果按 IP 缓存 7 天，减少重复请求并尊重免费接口限速。
class Crm::IpGeoResolver
  CACHE_TTL = 7.days
  API_URL = 'http://ip-api.com/json'.freeze

  # 返回 { country:, city: }（可能为空 hash）。
  def resolve(ip)
    return {} if ip.blank? || private_ip?(ip)

    Rails.cache.fetch("crm:ipgeo:#{ip}", expires_in: CACHE_TTL) do
      from_maxmind(ip) || from_api(ip) || {}
    end
  end

  private

  def private_ip?(ip)
    addr = IPAddr.new(ip)
    addr.loopback? || addr.private? || addr.link_local?
  rescue IPAddr::InvalidAddressError
    true
  end

  def from_maxmind(ip)
    geo = IpLookupService.new.perform(ip)
    return nil if geo.blank?

    country = geo.country.presence
    city = geo.city.presence
    return nil unless country || city

    { country: country, city: city }
  end

  def from_api(ip)
    resp = HTTParty.get("#{API_URL}/#{ip}",
                        query: { lang: 'zh-CN', fields: 'status,country,regionName,city' },
                        timeout: 3)
    data = resp.parsed_response
    return nil unless data.is_a?(Hash) && data['status'] == 'success'

    { country: data['country'].presence, city: data['city'].presence || data['regionName'].presence }
  rescue StandardError => e
    Rails.logger.warn("[Crm::IpGeoResolver] #{ip} lookup failed: #{e.message}")
    nil
  end
end
