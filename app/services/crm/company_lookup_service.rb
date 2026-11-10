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
  # 抓取总预算：agent 那条路径放宽到 90 秒，但那是整轮（含十几次模型往返）的额度，
  # 背调一个人不能把它吃光。超预算就用已经抓到的内容作答，不是报错。

  # scene 进 Apollo 台账：背调会走一次企业库（organizations/enrich），
  # 而「背调到底扣不扣 credits」正是要对账的问题之一，不标场景就查不出来。
  def initialize(account:, scene: 'bg_check')
    @account = account
    @scene = scene
  end

  def apollo = Crm::ApolloClient.new(account: @account, scene: @scene)

  # 返回 { status:, domain:, url:, profile:, enrichment: } —— status 取 invalid / public_domain / no_site / ok。
  # query 可为邮箱 / 域名 / 网址，统一解析出企业域名；enrichment 来自 Apollo 企业库（按域名，不依赖官网可爬）。
  def call(query:)
    domain = extract_domain(query)
    # 给的是公司名（没有点号）——先去企业库按名字找出域名再往下走。
    # 2026-10-30 之前这里直接判 invalid，于是 agent 拿着「B&B Group」这种只有公司名的
    # 线索什么都查不了，工具说明里却写着支持公司名。
    return lookup_by_name(query) if domain.blank?
    return { status: 'public_domain', domain: domain } if PUBLIC_DOMAINS.include?(domain)

    # ⚠️ **官网抓得到就不要买企业库那份**（2026-11-10 实测：organizations/enrich
    # 每调一次扣 1 个 Apollo credit，1:1，而挖公司和探词表一分不扣）。
    # 原来这一行写在抓官网之前、无条件先调——1219 次背调里 1194 次（98%）官网是抓得到的，
    # 那 98% 的 credits 买的是一份「锦上添花」：营收、行业代码、电话、领英在搜索阶段
    # 早就白给了，enrich 的边际价值只剩员工数和一条对账提示。
    # 真正需要它的是官网抓不到的那 2%，所以挪进 else 分支按需调。
    site = Crm::CompanySiteFetcher.new.call(domain)
    if site[:text].present?
      profile = Crm::EmailAiService.new(account: @account, purpose: 'lead_bg')
                                   .company_profile(domain: domain, site_text: site[:text])
      # 官网上的业务邮箱：和 VAT 一样从已经抓下来的正文里提，不额外发请求、不花 Apollo 的钱。
      # 解锁一个个人邮箱要一个 credit，而 sales@ 这类公开信箱是白给的（见 SiteContactFinder）。
      contacts = Crm::SiteContactFinder.call(site, domain: domain)
      return { status: 'ok', domain: domain, url: site[:url], profile: profile, enrichment: nil,
               vat: Crm::VatLookup.for(site[:legal_text].presence || site[:text], domain: domain),
               site_status: site[:status], site_emails: contacts.emails,
               contact_url: contacts.contact_url, enrichment_warning: nil }
    end

    enrichment = apollo.organization(domain: domain)
    if enrichment
      # 官网抓不到，但 Apollo 有这家公司 → 用企业库数据兜底，避免「背调不到」的死胡同。
      { status: 'ok', domain: domain, url: enrichment[:website], profile: profile_from_enrichment(enrichment), enrichment: enrichment }
    else
      # site[:status] 区分「站点不存在」和「站点存在但不让进」（451/403）。
      { status: 'no_site', domain: domain, site_status: site[:status] }
    end
  end

  private

  # 公司名 → 企业库候选 → 取最相关的一家，按它的域名走正常背调流程。
  # 候选列表一并带回去：同名公司很常见，让业务员看得到「我是按哪一家查的、还有哪几家」。
  def lookup_by_name(query)
    name = query.to_s.strip
    return { status: 'invalid' } if name.length < 2

    candidates = apollo.search_organizations(name: name)
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
end
