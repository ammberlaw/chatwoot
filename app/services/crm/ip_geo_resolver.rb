# 把 IP 解析成中文归属地（城市/国家），供邮件打开追踪展示「打开地点」。
# 优先本地 MaxMind 库（若配置了 IP_LOOKUP_API_KEY 下载了 DB），否则走免密钥在线接口。
# 在线接口用太平洋电脑网 pconline（国内服务器可达、返回中文，国外 IP 给国家、国内 IP 给省市）；
# 国内生产服务器访问不了 ip-api.com 之类国外接口，故不用它们。
# 私网/回环 IP 跳过；结果按 IP 缓存 7 天，减少重复请求。
class Crm::IpGeoResolver
  CACHE_TTL = 7.days
  PCONLINE_URL = 'https://whois.pconline.com.cn/ipJson.jsp'.freeze

  # 返回 { country:, city: }（可能为空 hash）。
  # 只缓存成功结果：偶发失败不写缓存，避免一次抖动把某 IP 的归属地锁死 7 天。
  def resolve(ip)
    return {} if ip.blank? || private_ip?(ip)

    key = "crm:ipgeo:#{ip}"
    cached = Rails.cache.read(key)
    return cached if cached.present?

    result = from_maxmind(ip) || from_pconline(ip) || {}
    Rails.cache.write(key, result, expires_in: CACHE_TTL) if result.present?
    result
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

  # pconline 返回 GBK 编码 JSON：国内有 pro/city（省/市），国外 pro/city 为空、addr 里是国家名。
  def from_pconline(ip)
    resp = HTTParty.get(PCONLINE_URL, query: { ip: ip, json: true }, timeout: 4)
    body = resp.body.to_s.dup.force_encoding('GB18030').encode('UTF-8', invalid: :replace, undef: :replace)
    data = JSON.parse(body)
    return nil unless data.is_a?(Hash)

    pro = data['pro'].to_s.strip
    city = data['city'].to_s.strip
    return { country: '中国', city: (city.presence || pro) } if pro.present? || city.present?

    country = data['addr'].to_s.strip.presence
    country ? { country: country, city: nil } : nil
  rescue StandardError => e
    Rails.logger.warn("[Crm::IpGeoResolver] pconline #{ip} lookup failed: #{e.message}")
    nil
  end
end
