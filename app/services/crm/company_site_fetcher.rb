# 抓一家公司的官网正文，供背调用。
#
# 从 Crm::CompanyLookupService 拆出来：那边负责「拿到正文之后怎么判断」，
# 这边只负责「怎么把正文弄到手」——两件事的坑完全不同，混在一个类里也超了行数上限。
class Crm::CompanySiteFetcher
  FETCH_TIMEOUT = 6       # 首页抓取超时（秒）
  SUB_PAGE_TIMEOUT = 5    # 子页抓取超时（秒）
  MAX_SUB_PAGES = 4       # 最多再抓几个子页
  FETCH_BUDGET = 18
  MAX_SITE_TEXT = 6000      # 首页正文上限
  MAX_SUB_PAGE_TEXT = 3200  # 单个子页上限——别让一个产品列表页把法律页挤掉
  # 法律信息页单独给大配额：这一页前几千字常常全是站点导航菜单，法人实体、注册地址、
  # 负责人排在后面。用 3200 去截，模型看到的就只有一张产品目录。
  # 2026-11-07 data-modul.com 的「地址/负责人」读不出来，根子就在这儿。
  LEGAL_BLOCK_TEXT = 8000
  LEGAL_SCAN_TEXT = 40_000  # 法律信息页额外留一份长的，只给税号提取用，不进模型
  MAX_TOTAL_TEXT = 15_000   # 送模型的总文本上限
  USER_AGENT = 'Mozilla/5.0 (compatible; WintouchCRM/1.0; +https://wintouchspace.com)'.freeze

  # 子页抓取优先级。法律声明页排第一：德国《电信媒体法》第 5 条强制每个商业网站都要有
  # Impressum，法人实体全称、注册地址、Geschäftsführer（负责人）都写在那一页，首页永远没有。
  # 其余欧洲国家有同类页面（法国 mentions légales、西班牙 aviso legal）。
  # 只认首页上真实存在的链接，不去盲猜路径——猜错一次就白白花掉 5 秒预算。
  SUB_PAGE_PATTERNS = [
    # ⚠️ 每多一个语言的写法，就多一批公司能查到法人全称和税号。2026-11-07 补 imprint：
    # 德国公司的英文站把这页叫 Imprint，漏了它等于这批公司的法律页从来没抓过。
    ['法律信息页',
     /impressum|imprint|legal[-_ ]?notice|mentions[-_ ]?legales|aviso[-_ ]?legal|
      note[-_ ]?legali|informazioni[-_ ]?legali|colofon|rechtliche|juridisch/xi],
    ['关于我们', /about|ueber[-_ ]?uns|über[-_ ]?uns|unternehmen|company|qui[-_ ]?sommes/i],
    ['产品线', /product|produkte|katalog|catalog|sortiment|brand|marken/i],
    ['联系方式', /contact|kontakt|contacto/i]
  ].freeze

  # 返回 { url:, text:, legal_text: }。抓不到正文时 text 为 nil，不报错。
  def call(domain)
    fetch_website(domain)
  end

  private

  # 首页 + 几个关键子页。
  #
  # 原来只抓首页，结果是背调永远只能说「这家公司是做什么的」，说不出法人实体、
  # 注册地址、负责人、产品线——那些内容首页本来就不写。欧洲公司的法律信息页
  # （Impressum）是法律强制页，恰恰把这些全列齐了。
  def fetch_website(domain)
    home = fetch_home(domain)
    return { url: nil, text: nil, status: home[:status] } if home[:text].blank?

    sub = sub_page_blocks(home)
    blocks = ["【首页】\n#{home[:text]}"] + sub[:blocks]
    { url: home[:url], text: blocks.join("\n\n")[0, MAX_TOTAL_TEXT],
      legal_text: sub[:legal_text], status: home[:status] }
  end

  # 依次尝试 https://域名 → https://www.域名 → http:// 两种，任一抓到正文即返回
  # （html 留着解析子页链接）。
  # 顺手把 HTTP 状态记下来。抓不到正文有两种完全不同的原因：
  # 「站点不存在」和「站点存在但不让我们进」（451 地区封锁、403 反爬），
  # 后者业务员点进去同样打不开，该在列表上提前告诉他，别让他白点。
  # 2026-11-08 实测 toysrus.es 返回 451，正文只有一个「451」。
  def fetch_home(domain)
    last_status = nil
    # ⚠️ **http 兜底不能省。**
    # 欧洲中小分销商有不少官网至今没有证书，只听 80 端口。只试 https 的话
    # 这批公司的背调永远是「抓不到正文」，而且列表上的链接拼成 https 点进去
    # 会被 Chrome 的「HTTPS 优先」拦下来报「此网站不支持安全连接」——
    # 业务员看到的是一屏警告，不是客户官网（2026-11-08 用户反馈）。
    %W[https://#{domain} https://www.#{domain} http://#{domain} http://www.#{domain}].each do |url|
      res = fetch_page(url, FETCH_TIMEOUT)
      last_status = res[:status] if res[:status]
      text = extract_text(res[:html], MAX_SITE_TEXT)
      return { url: url, html: res[:html], text: text, status: res[:status] } if text.present?
    end
    { url: nil, html: nil, text: nil, status: last_status }
  end

  # Accept-Language 要带：多语站点按来访 IP 发语言，我们的服务器在国内，
  # 不声明就会拿到对方的**中文站**——实测 phoenixcontact 抓回来的是中国子公司的
  # 法人实体和南京地址，而做外贸要的是德国母公司那一份。
  REQUEST_HEADERS = {
    'User-Agent' => USER_AGENT,
    'Accept-Language' => 'en-US,en;q=0.9,de;q=0.8'
  }.freeze

  def fetch_html(url, timeout)
    fetch_page(url, timeout)[:html]
  end

  def fetch_page(url, timeout)
    res = HTTParty.get(url, timeout: timeout, follow_redirects: true, headers: REQUEST_HEADERS)
    { html: res.body, status: res.code }
  rescue StandardError => e
    Rails.logger.info("[Crm::CompanyLookup] fetch #{url} failed: #{e.class}")
    { html: nil, status: nil }
  end

  # 按优先级抓子页，超出时间预算就停——拿到几页算几页，不报错。
  #
  # ⚠️ 必须 each + 累加，不能写成 filter_map：filter_map 里 break 出来整个表达式是 nil，
  # 不是已经抓到的那几页，上游 `[首页] + nil` 直接崩（生产 2026-11-03 背调 steliau.fr
  # 报 no implicit conversion of nil into Array，就是慢站吃满预算触发的）。
  def sub_page_blocks(home)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FETCH_BUDGET
    blocks = []
    legal_text = nil
    pick_sub_pages(home[:html], home[:url]).each do |label, url|
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      html = fetch_html(url, SUB_PAGE_TIMEOUT)
      # 法律信息页单独留一份**没截断**的原文给税号提取。
      # 这一页前几千字常常全是站点导航菜单，法人实体和税号排在后面，
      # 用给模型的那份（MAX_SUB_PAGE_TEXT）去找，正好把真东西切掉。
      legal = label == '法律信息页'
      legal_text ||= extract_text(html, LEGAL_SCAN_TEXT) if legal
      text = extract_text(html, legal ? LEGAL_BLOCK_TEXT : MAX_SUB_PAGE_TEXT)
      blocks << "【#{label}】#{url}\n#{text}" if text.present?
    end
    { blocks: blocks, legal_text: legal_text }
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
  # ⚠️ 比主机名必须先把 www. 去掉。
  # fetch_home 先试不带 www 的地址，成功就用它当 base；但很多站点（WordPress 尤其）
  # 页面里的链接一律写成 https://www.xxx.com/...。严格相等的话整站链接一条都过不了，
  # 结果是「首页抓到了、一个子页都没有」——看起来像站点没有子页，其实是比错了。
  # 2026-11-07 实测 lang-ag.com：首页 63 个链接（含 /impressum/）全被这一行挡掉。
  def same_site_page?(uri, base)
    bare(uri.host) == bare(base.host) && uri.scheme&.start_with?('http') &&
      uri.path.present? && uri.path != '/'
  end

  def bare(host) = host.to_s.downcase.delete_prefix('www.')

  # ⚠️ 块级元素之间必须补一个换行，否则 Nokogiri 的 .text 会把相邻块的文字**黏成一串**：
  # 「Amtsgericht Köln」+「Registernummer:」变成「KölnRegisternummer:」，
  # 三个总经理的名字连成「Peter HeinrichsMarkus KieferMarian Müller」。
  # 模型看到这种糊成一团的文本只会答「未提及」——2026-11-07 itz-display.solutions
  # 的法人全称、注册地址、负责人三项全军覆没，查下来根子就在这一行。
  BLOCK_TAGS = 'p,div,li,tr,td,th,h1,h2,h3,h4,h5,h6,section,article,header,footer,address,br,dd,dt'.freeze

  # 提取可读文本：标题 + meta 描述 + 正文，去掉脚本/样式，压缩空白后截断。
  def extract_text(html, limit)
    return '' if html.blank?

    doc = Nokogiri::HTML(html)
    doc.css('script, style, noscript, svg').remove
    doc.css(BLOCK_TAGS).each { |node| node.after("\n") }
    parts = ["标题：#{doc.at_css('title')&.text.to_s.strip}", description_line(doc),
             doc.css('body').text.gsub(/\s+/, ' ').strip].compact
    parts.join("\n").strip[0, limit].to_s
  end

  def description_line(doc)
    desc = doc.at_css('meta[name="description"]')&.[]('content').to_s.strip
    "描述：#{desc}" if desc.present?
  end
end
