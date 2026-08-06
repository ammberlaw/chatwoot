# 客户 AI 背调：输入一个邮箱，取其企业后缀域名，抓取该公司官网正文，交 Crm::EmailAiService
# 判断这家公司是做什么的、规模多大、是否为真实运营公司。个人/公共邮箱（gmail/qq 等）直接拦截，
# 因为它们没有对应的企业官网。抓取失败（网站是纯前端渲染、防爬、无官网）时返回 no_site，不报错。
class Crm::CompanyLookupService
  # 常见个人/公共邮箱域名：这类邮箱后缀不是企业官网，查不出公司背景。
  PUBLIC_DOMAINS = %w[
    gmail.com googlemail.com outlook.com hotmail.com live.com msn.com
    yahoo.com yahoo.com.cn ymail.com aol.com icloud.com me.com gmx.com
    qq.com foxmail.com 163.com 126.com yeah.net sina.com sina.cn sohu.com
    139.com 189.cn aliyun.com protonmail.com proton.me mail.com zoho.com
  ].freeze

  FETCH_TIMEOUT = 6       # 单次抓取超时（秒），双候选域名总计控制在 15s 生产超时内
  MAX_SITE_TEXT = 6000    # 送模型的官网文本上限
  USER_AGENT = 'Mozilla/5.0 (compatible; WintouchCRM/1.0; +https://wintouchspace.com)'.freeze

  def initialize(account:)
    @account = account
  end

  # 返回 { status:, domain:, url:, profile:, enrichment: } —— status 取 invalid / public_domain / no_site / ok。
  # query 可为邮箱 / 域名 / 网址，统一解析出企业域名；enrichment 来自 Apollo 企业库（按域名，不依赖官网可爬）。
  def call(query:)
    domain = extract_domain(query)
    return { status: 'invalid' } if domain.blank?
    return { status: 'public_domain', domain: domain } if PUBLIC_DOMAINS.include?(domain)

    enrichment = Crm::ApolloClient.new(account: @account).organization(domain: domain)

    site = fetch_website(domain)
    if site[:text].present?
      profile = Crm::EmailAiService.new(account: @account).company_profile(domain: domain, site_text: site[:text])
      { status: 'ok', domain: domain, url: site[:url], profile: profile, enrichment: enrichment }
    elsif enrichment
      # 官网抓不到，但 Apollo 有这家公司 → 用企业库数据兜底，避免「背调不到」的死胡同。
      { status: 'ok', domain: domain, url: enrichment[:website], profile: profile_from_enrichment(enrichment), enrichment: enrichment }
    else
      { status: 'no_site', domain: domain }
    end
  end

  private

  # 无官网正文时，用 Apollo 企业库数据拼出与 AI 背调同结构的 profile，供前端头卡/字段网格复用。
  # 能进 Apollo 企业库且有员工数或领英，视作真实运营公司。
  def profile_from_enrichment(enrichment)
    {
      'company_name' => enrichment[:name],
      'legit' => (enrichment[:employees].to_i.positive? || enrichment[:linkedin].present?) ? 'real' : 'unknown',
      'business' => enrichment[:description],
      'industry' => enrichment[:industry],
      'size_hint' => enrichment[:employees] ? "约 #{enrichment[:employees]} 人" : nil,
      'country' => enrichment[:country]
    }.compact
  end

  # 从邮箱 / 域名 / 网址里解析出企业域名：邮箱取 @ 后段；域名/网址剥掉协议、路径、端口与 www 前缀。
  def extract_domain(query)
    raw = query.to_s.strip.downcase
    return if raw.blank?

    raw = raw.split('@').last.to_s if raw.include?('@')
    raw = raw.sub(%r{\Ahttps?://}, '').sub(%r{[/:?].*\z}, '').sub(/\Awww\./, '')
    raw.include?('.') ? raw.presence : nil
  end

  # 依次尝试 https://域名 与 https://www.域名，任一抓到正文即返回。
  def fetch_website(domain)
    %W[https://#{domain} https://www.#{domain}].each do |url|
      html = HTTParty.get(url, timeout: FETCH_TIMEOUT, follow_redirects: true,
                               headers: { 'User-Agent' => USER_AGENT }).body
      text = extract_text(html)
      return { url: url, text: text } if text.present?
    rescue StandardError => e
      Rails.logger.info("[Crm::CompanyLookup] fetch #{url} failed: #{e.class}")
      next
    end
    { url: nil, text: nil }
  end

  # 提取官网可读文本：标题 + meta 描述 + 正文，去掉脚本/样式，压缩空白后截断。
  def extract_text(html)
    return '' if html.blank?

    doc = Nokogiri::HTML(html)
    doc.css('script, style, noscript, svg').remove
    title = doc.at_css('title')&.text.to_s.strip
    desc = doc.at_css('meta[name="description"]')&.[]('content').to_s.strip
    body = doc.css('body').text.gsub(/\s+/, ' ').strip
    parts = ["标题：#{title}", ("描述：#{desc}" if desc.present?), body].compact
    parts.join("\n").strip[0, MAX_SITE_TEXT].to_s
  end
end
