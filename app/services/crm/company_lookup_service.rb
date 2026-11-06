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

  THIN_EMPLOYEE_MAX = 10  # 少于这个人数且没有营收，视作「薄记录」，才去比对是否匹配错了公司
  FETCH_TIMEOUT = 6       # 首页抓取超时（秒）
  SUB_PAGE_TIMEOUT = 5    # 子页抓取超时（秒）
  MAX_SUB_PAGES = 4       # 最多再抓几个子页
  # 抓取总预算：agent 那条路径放宽到 90 秒，但那是整轮（含十几次模型往返）的额度，
  # 背调一个人不能把它吃光。超预算就用已经抓到的内容作答，不是报错。
  FETCH_BUDGET = 18
  MAX_SITE_TEXT = 6000      # 首页正文上限
  MAX_SUB_PAGE_TEXT = 3200  # 单个子页上限——别让一个产品列表页把法律页挤掉
  MAX_TOTAL_TEXT = 15_000   # 送模型的总文本上限
  USER_AGENT = 'Mozilla/5.0 (compatible; WintouchCRM/1.0; +https://wintouchspace.com)'.freeze

  # 子页抓取优先级。法律声明页排第一：德国《电信媒体法》第 5 条强制每个商业网站都要有
  # Impressum，法人实体全称、注册地址、Geschäftsführer（负责人）都写在那一页，首页永远没有。
  # 其余欧洲国家有同类页面（法国 mentions légales、西班牙 aviso legal）。
  # 只认首页上真实存在的链接，不去盲猜路径——猜错一次就白白花掉 5 秒预算。
  SUB_PAGE_PATTERNS = [
    ['法律信息页', /impressum|legal[-_ ]?notice|mentions[-_ ]?legales|aviso[-_ ]?legal|colofon/i],
    ['关于我们', /about|ueber[-_ ]?uns|über[-_ ]?uns|unternehmen|company|qui[-_ ]?sommes/i],
    ['产品线', /product|produkte|katalog|catalog|sortiment|brand|marken/i],
    ['联系方式', /contact|kontakt|contacto/i]
  ].freeze

  def initialize(account:)
    @account = account
  end

  # 返回 { status:, domain:, url:, profile:, enrichment: } —— status 取 invalid / public_domain / no_site / ok。
  # query 可为邮箱 / 域名 / 网址，统一解析出企业域名；enrichment 来自 Apollo 企业库（按域名，不依赖官网可爬）。
  def call(query:)
    domain = extract_domain(query)
    # 给的是公司名（没有点号）——先去企业库按名字找出域名再往下走。
    # 2026-10-30 之前这里直接判 invalid，于是 agent 拿着「B&B Group」这种只有公司名的
    # 线索什么都查不了，工具说明里却写着支持公司名。
    return lookup_by_name(query) if domain.blank?
    return { status: 'public_domain', domain: domain } if PUBLIC_DOMAINS.include?(domain)

    enrichment = Crm::ApolloClient.new(account: @account).organization(domain: domain)

    site = fetch_website(domain)
    if site[:text].present?
      profile = Crm::EmailAiService.new(account: @account).company_profile(domain: domain, site_text: site[:text])
      { status: 'ok', domain: domain, url: site[:url], profile: profile, enrichment: enrichment,
        enrichment_warning: enrichment_warning(enrichment, site[:text], profile) }
    elsif enrichment
      # 官网抓不到，但 Apollo 有这家公司 → 用企业库数据兜底，避免「背调不到」的死胡同。
      { status: 'ok', domain: domain, url: enrichment[:website], profile: profile_from_enrichment(enrichment), enrichment: enrichment }
    else
      { status: 'no_site', domain: domain }
    end
  end

  private

  # 公司名 → 企业库候选 → 取最相关的一家，按它的域名走正常背调流程。
  # 候选列表一并带回去：同名公司很常见，让业务员看得到「我是按哪一家查的、还有哪几家」。
  def lookup_by_name(query)
    name = query.to_s.strip
    return { status: 'invalid' } if name.length < 2

    candidates = Crm::ApolloClient.new(account: @account).search_organizations(name: name)
    return { status: 'name_not_found', name: name } if candidates.blank?

    picked = confident_match(name, candidates)
    # 名字对不上就**不往下查**，把候选摆出来让人挑。
    # Apollo 的按名搜索是模糊匹配：「B&B Group」返回的第一条是 B. Braun（德国医疗巨头），
    # 照着它查会得到一份详尽、可信、但完全是另一家公司的背调——比查不到糟得多。
    return { status: 'name_candidates', name: name, candidates: candidates.first(5) } if picked.nil?

    call(query: picked[:domain]).merge(
      matched_by_name: name, picked_candidate: picked, candidates: candidates.first(5)
    )
  end

  # 只有两种情况敢直接往下查：企业库只返回一家；或者第一条的名字跟他给的名字**归一化后一致**。
  def confident_match(name, candidates)
    return candidates.first if candidates.size == 1

    key = name_key(name)
    candidates.find { |c| name_key(c[:name]) == key }
  end

  # 归一化：转小写、去掉公司后缀与标点，只留词干序列。
  # 「B&B Group」→ "b b"；「B. Braun Group」→ "b braun"，两者不等，于是不会被当成同一家。
  LEGAL_SUFFIXES = /\b(gmbh|ag|kg|ohg|mbh|ltd|limited|inc|llc|corp|corporation|co|company|group|holding|sa|sl|bv|nv|srl|spa|pte|pty)\b/i

  def name_key(raw)
    raw.to_s.downcase.gsub(LEGAL_SUFFIXES, ' ').gsub(/[^a-z0-9\u4e00-\u9fa5]+/, ' ').strip.squeeze(' ')
  end

  # Apollo 按域名匹配偶尔会命中「同名但不是同一家」的公司——kis-fr.com 命中的是一家 4 人的同名
  # SAP 咨询公司，而官网讲的是 390 人的照相亭厂商。两家的信息拼在同一张卡片上最容易误导人，
  # 所以这里只做一件事：把对不上的迹象标出来，让人自己判断，不替他下结论、也不擅自丢弃数据。
  # 只在「记录很薄」（不足 10 人且无营收）且至少有一处对不上时才提示，避免正常的小公司被误伤。
  def enrichment_warning(enrichment, site_text, profile)
    return if enrichment.blank?
    return unless enrichment[:employees].to_i < THIN_EMPLOYEE_MAX && enrichment[:revenue].blank?

    haystack = "#{site_text} #{Array(profile.is_a?(Hash) ? profile.values : nil).join(' ')}".downcase
    reasons = []
    city = enrichment[:city].to_s.downcase
    reasons << "企业库登记的城市（#{enrichment[:city]}）在官网里没出现" if city.present? && haystack.exclude?(city)
    reasons << '企业库的业务关键词与官网内容没有一处重合' if keywords_unrelated?(enrichment[:keywords], haystack)
    return if reasons.empty?

    { suspect: true, reasons: reasons, company_name: enrichment[:name] }
  end

  # 关键词一个都对不上才算「无关」；只比长度大于 3 的词，避开 the/and/sas 这类噪音。
  def keywords_unrelated?(keywords, haystack)
    words = Array(keywords).flat_map { |k| k.to_s.downcase.split(/[^a-z0-9\u4e00-\u9fa5]+/) }
                           .select { |w| w.length > 3 }.uniq
    words.any? && words.none? { |w| haystack.include?(w) }
  end

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

  # 首页 + 几个关键子页。
  #
  # 原来只抓首页，结果是背调永远只能说「这家公司是做什么的」，说不出法人实体、
  # 注册地址、负责人、产品线——那些内容首页本来就不写。欧洲公司的法律信息页
  # （Impressum）是法律强制页，恰恰把这些全列齐了。
  def fetch_website(domain)
    home = fetch_home(domain)
    return { url: nil, text: nil } if home[:text].blank?

    blocks = ["【首页】\n#{home[:text]}"] + sub_page_blocks(home)
    { url: home[:url], text: blocks.join("\n\n")[0, MAX_TOTAL_TEXT] }
  end

  # 依次尝试 https://域名 与 https://www.域名，任一抓到正文即返回（html 留着解析子页链接）。
  def fetch_home(domain)
    %W[https://#{domain} https://www.#{domain}].each do |url|
      html = fetch_html(url, FETCH_TIMEOUT)
      text = extract_text(html, MAX_SITE_TEXT)
      return { url: url, html: html, text: text } if text.present?
    end
    { url: nil, html: nil, text: nil }
  end

  # Accept-Language 要带：多语站点按来访 IP 发语言，我们的服务器在国内，
  # 不声明就会拿到对方的**中文站**——实测 phoenixcontact 抓回来的是中国子公司的
  # 法人实体和南京地址，而做外贸要的是德国母公司那一份。
  REQUEST_HEADERS = {
    'User-Agent' => USER_AGENT,
    'Accept-Language' => 'en-US,en;q=0.9,de;q=0.8'
  }.freeze

  def fetch_html(url, timeout)
    HTTParty.get(url, timeout: timeout, follow_redirects: true, headers: REQUEST_HEADERS).body
  rescue StandardError => e
    Rails.logger.info("[Crm::CompanyLookup] fetch #{url} failed: #{e.class}")
    nil
  end

  # 按优先级抓子页，超出时间预算就停——拿到几页算几页，不报错。
  #
  # ⚠️ 必须 each + 累加，不能写成 filter_map：filter_map 里 break 出来整个表达式是 nil，
  # 不是已经抓到的那几页，上游 `[首页] + nil` 直接崩（生产 2026-11-03 背调 steliau.fr
  # 报 no implicit conversion of nil into Array，就是慢站吃满预算触发的）。
  def sub_page_blocks(home)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FETCH_BUDGET
    blocks = []
    pick_sub_pages(home[:html], home[:url]).each do |label, url|
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      text = extract_text(fetch_html(url, SUB_PAGE_TIMEOUT), MAX_SUB_PAGE_TEXT)
      blocks << "【#{label}】#{url}\n#{text}" if text.present?
    end
    blocks
  end

  # 只认首页上真实存在的同站链接，每类取第一个命中的，最多 MAX_SUB_PAGES 个。
  #
  # ⚠️ 只拿**路径**去匹，不能拿整条 URL：phoenixcontact.com 这种域名本身就含 contact，
  # 用整条 URL 匹的话它家每一个链接都命中「联系方式」，第一条往往就是首页。
  def pick_sub_pages(html, base_url)
    links = same_site_links(html, base_url).reject { |href| href == base_url }
    picked = []
    SUB_PAGE_PATTERNS.each do |label, pattern|
      hit = links.find { |href| pattern.match?(path_of(href)) && picked.none? { |_, taken| taken == href } }
      picked << [label, hit] if hit
    end
    picked.first(MAX_SUB_PAGES)
  end

  def path_of(url)
    uri = URI.parse(url)
    "#{uri.path}?#{uri.query}"
  rescue StandardError
    ''
  end

  def same_site_links(html, base_url)
    return [] if html.blank? || base_url.blank?

    base = URI.parse(base_url)
    Nokogiri::HTML(html).css('a[href]').filter_map { |a| absolute_same_host(a['href'], base) }.uniq
  rescue URI::InvalidURIError
    []
  end

  SKIP_HREF_PREFIXES = ['#', 'mailto:', 'tel:', 'javascript:'].freeze

  def absolute_same_host(href, base)
    return nil if href.blank? || href.start_with?(*SKIP_HREF_PREFIXES)

    uri = URI.join(base, href)
    uri.fragment = nil
    same_site_page?(uri, base) ? uri.to_s : nil
  rescue StandardError
    nil
  end

  # 同站、http(s)、且不是首页本身——"/#contact" 这类锚点去掉 fragment 后就落回首页，
  # 抓它只会拿到一份重复内容，还白花一次预算。
  def same_site_page?(uri, base)
    uri.host == base.host && uri.scheme&.start_with?('http') &&
      uri.path.present? && uri.path != '/'
  end

  # 提取可读文本：标题 + meta 描述 + 正文，去掉脚本/样式，压缩空白后截断。
  def extract_text(html, limit)
    return '' if html.blank?

    doc = Nokogiri::HTML(html)
    doc.css('script, style, noscript, svg').remove
    title = doc.at_css('title')&.text.to_s.strip
    desc = doc.at_css('meta[name="description"]')&.[]('content').to_s.strip
    body = doc.css('body').text.gsub(/\s+/, ' ').strip
    parts = ["标题：#{title}", ("描述：#{desc}" if desc.present?), body].compact
    parts.join("\n").strip[0, limit].to_s
  end
end
