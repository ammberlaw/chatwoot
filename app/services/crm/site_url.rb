# 拼一个**点得开**的官网地址。
#
# 为什么要单独一个类：这件事有两个反直觉的坑，而线索列表、建档、背调三处都要用，
# 各写一遍必然走偏。
#
# 坑一：**Apollo 的 website_url 一律是 `http://www.域名`**，那是它自己的归一化写法，
# 跟网站真实协议毫无关系。直接拿来当链接，Chrome 的「HTTPS 优先」会把每一条都拦成
# 「此网站不支持安全连接」——不是个别网站的问题，是全部（2026-11-08 用户反馈）。
# 所以它的**主机名要**（告诉我们这家要不要带 www，xploretech.com 就是裸域名没有 A 记录），
# 协议**不要**。
#
# 坑二：少数欧洲小分销商的站至今只有 http。这种只能靠背调实测——
# Crm::CompanySiteFetcher 会把真正抓通的那个地址记在 bg.url 里，有就用它。
class Crm::SiteUrl
  SCHEME = %r{\Ahttps?://}i

  # bg_url：背调实测抓通的地址（最可信）；website：Apollo 给的；domain：兜底。
  def self.for(domain: nil, website: nil, bg_url: nil)
    return bg_url if bg_url.present?

    host = host_of(website) || domain.presence
    "https://#{host}" if host.present?
  end

  def self.host_of(website)
    website.to_s.strip.sub(SCHEME, '').presence
  end
  private_class_method :host_of
end
