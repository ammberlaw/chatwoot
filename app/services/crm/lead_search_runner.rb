# 按画像生成的关键词去搜潜在客户，把结果落成线索。
#
# 两段：
#   ① 按「目标市场 + 关键词」搜公司（不扣 credits）
#   ② 对每家公司按域名搜联系人（不扣 credits，只拿到名字半遮 + has_email）
# 真邮箱要人点了才解锁（Crm::LeadUnlock），那一步才花钱。
#
# 为什么不搜到就全解锁：一次任务几百条，全解既烧额度，也没人看得过来。
# 业务员扫一眼公司名和职位就能筛掉一大半——让他先筛，再解锁他看中的。
class Crm::LeadSearchRunner
  # 一个任务最多自动背调多少家。每家约 30 秒，封顶是防它把低优先队列占太久。
  # 2026-11-08 从 60 提到 90：unsure 也要排了（见 enqueue_bg_checks），需求翻了一倍。
  # 背调跑在 deferred（最低优先级），占半小时不影响任何业务队列。
  BG_CHECK_CAP = 90
  PEOPLE_PER_COMPANY = 3

  # 优先找这些岗位的人。搜出一堆工程师和前台没用，要找拍板买的。
  # 第一档：采购口。主力市场在欧洲，所以带上当地职位词——
  # 德国中小企业的采购岗常常就写 Einkauf / Einkaufsleiter，不写英文。
  TARGET_TITLES = ['purchasing manager', 'procurement manager', 'buyer',
                   'sourcing manager', 'category manager', 'owner', 'ceo',
                   'head of purchasing', 'purchasing director', 'procurement director',
                   'einkaufsleiter', 'einkauf', 'responsable achats', 'acheteur',
                   'responsabile acquisti', 'director de compras', 'inkoop'].freeze

  # 第二档：采购口一个人都搜不到时才用。
  # 2026-11-07 实测：42 家值得跟的公司里 19 家（45%）按采购职位搜回来是空的——
  # 不是没人，是小公司根本没人挂「采购经理」的头衔，老板自己拍板
  # （lcd-module.com 三个 Managing Director、brightav.com 一个 President）。
  # ⚠️ 绝不退到「完全不限职位」：那样 mvix.com 搜回来的头两个是 HR 和用户体验总监。
  FALLBACK_TITLES = ['managing director', 'geschäftsführer', 'general manager',
                     'president', 'vice president', 'country manager',
                     'sales director', 'head of sales', 'business development manager',
                     'product manager', 'operations manager'].freeze

  def initialize(campaign:)
    @campaign = campaign
    @account = campaign.account
    @client = Crm::ApolloClient.new(account: @account)
  end

  # 返回新建的线索条数。
  def call
    return 0 unless @client.configured? && @campaign.keywords.present?

    @campaign.update!(status: 'SEARCHING', last_error: nil)
    companies = collect_companies
    # ⚠️ 初筛必须在抓联系人**之前**：判断要的东西（公司名/域名/行业代码/营收/门店数）
    # 搜索阶段全都有了，一个都不来自联系人。2026-11-07 改这个顺序之前，
    # 73 家公司里 53 家被判「不是买家」，而联系人是挨家都搜过的——七成调用白花。
    verdicts = Crm::LeadScreener.verdicts_for(account: @account, items: screen_items(companies),
                                              product_hint: @campaign.product_hint,
                                              criteria: @campaign.screen_criteria)
    created = companies.sum { |company| harvest_company(company, verdicts[company[:name]]) }
    # 兜底：初筛那一批 AI 调用万一失败，没判到的公司不能就这么漏成「没结论」。
    Crm::LeadScreener.new(campaign: @campaign).call
    enqueue_bg_checks
    # 跑完给每个搜索词评级（好词/可用/弱词/废词/待观察），废词下一轮不再占配额。
    Crm::KeywordGrade.new(campaign: @campaign.reload).stamp!
    @campaign.update!(status: 'DONE', searched_at: Time.current)
    created
  rescue StandardError => e
    @campaign.update(status: 'PROFILED', last_error: error_text(e).truncate(300))
    0
  end

  # 额度耗尽那句原样摆到任务上，不带类名前缀——这句是给人看的，不是异常现场：
  # 看到「余额用完，X 月 X 日恢复」才不会去翻关键词是不是配错了。
  def error_text(err)
    err.is_a?(Crm::ApolloClient::CreditsExhausted) ? err.message : "#{err.class}: #{err.message}"
  end

  private

  # 按市场 × 关键词搜公司，按域名去重。同一家公司被好几个关键词搜到很常见，
  # 去重之后才是真实的候选规模。
  # 判「像买家」和「看不出」的都自动排队背调，一家公司一个 job（见 Crm::LeadBgCheckJob）。
  #
  # ⚠️ unsure **必须也排**。2026-11-08 之前只给 yes 排，理由是「unsure 本来就要人看一眼」——
  # 实测结果是任务 6/7/8 攒下 458 家 unsure（比 yes 的 399 还多），既没人看、
  # 也没有任何新信息进来帮它们脱离 unsure，等于凭空沉掉一半产出。
  # 而背调恰恰就是解 unsure 的那把钥匙：unsure 的意思是「只看名字看不出」，
  # 背调读的是官网。背调回来再由 Crm::LeadRescreen 重判一次。
  #
  # yes 排在前面：额度有限时先保证最可能成的那批。
  def enqueue_bg_checks
    picked = (bg_candidates('yes') + bg_candidates('unsure')).uniq(&:domain).first(BG_CHECK_CAP)
    picked.each { |lead| Crm::LeadBgCheckJob.perform_later(lead.id) }
    # 背调要跑十几二十分钟，重判得跟在后面自己续（见 Crm::LeadRescreenJob）。
    Crm::LeadRescreenJob.set(wait: 5.minutes).perform_later(@campaign.id) if picked.any?
  end

  def bg_candidates(verdict)
    @campaign.leads.where("raw->>'screen' = ?", verdict).where.not(domain: nil)
             .where("NOT (raw ? 'bg')").select(:id, :domain).uniq(&:domain)
  end

  # ⚠️ 额度要**按市场分**，不能用一个总数。
  # 2026-11-08 之前这里是 `break if seen.size >= MAX_COMPANIES`，外层按市场顺序遍历——
  # 排第一的市场十个关键词就把总额度吃光，后面的市场一家都轮不到，而且**悄无声息**：
  # 任务设了「意大利+美国+法国」，搜回来 168 条全是意大利。
  # Apollo 的 organization_locations 要的是英文国家名，不是我们的枚举值。
  # ⚠️ 缩写要特判：直接 capitalize 会把 USA 变成「Usa」、UK 变成「Uk」，
  # 这个串既送给 Apollo 也原样存进线索的 country 列，界面上就是一个错别字。
  ACRONYMS = { 'USA' => 'USA', 'UK' => 'UK', 'UAE' => 'UAE' }.freeze

  def country_name(market)
    key = market.to_s.upcase
    ACRONYMS[key] || key.split('_').map(&:capitalize).join(' ')
  end

  # 判「不是买家」：已经有线索的只更新结论就够了，再建一条空占位只会多一行废话。
  def skip_contacts(company, dup_id, verdict)
    return 0 if company_leads(company).exists?

    create_lead(company, nil, dup_id, verdict)
  end

  # 把这一轮的初筛结论同步到已有线索。人工动过的（已建档／已丢弃）一律不碰——
  # 人的判断优先级高于模型，这是整套东西的一条底线。
  def refresh_verdict(company, verdict)
    return if verdict.blank?

    company_leads(company).find_each do |lead|
      lead.update_columns(raw: lead.raw.merge('screen' => verdict[:verdict], # rubocop:disable Rails/SkipsModelValidations
                                              'screen_why' => verdict[:why]))
    end
  end

  # 同一家公司在本任务下的线索（按域名，没域名退回公司名）。只取没被人动过的。
  def company_leads(company)
    scope = @account.crm_leads.where(crm_lead_campaign_id: @campaign.id, status: %w[FOUND UNLOCKED])
    company[:domain].present? ? scope.where(domain: company[:domain]) : scope.where(company_name: company[:name])
  end

  # 只删「没有联系人」的那条占位，人工动过的（已建档/已丢弃）一律不碰。
  def drop_placeholder(domain)
    @account.crm_leads.where(crm_lead_campaign_id: @campaign.id, domain: domain,
                             person_name: nil, status: %w[FOUND UNLOCKED]).delete_all
  end

  # 送去初筛的一行料。行业从 NAICS 代码翻过来（Apollo 的 industry 字段搜索接口不给）。
  def screen_items(companies)
    companies.map do |c|
      { name: c[:name], domain: c[:domain], industry: Crm::NaicsLabel.for(c[:naics]),
        revenue: c[:revenue], retail: c[:retail_locations], listed: c[:listed] }
    end
  end

  # 一家公司 → 若干条线索（一个联系人一条）。没有域名就搜不了人，
  # 只留公司本身当线索（业务员可以自己去查官网）。
  #
  # 判「不是买家」的**不抓联系人**，但仍然建一条线索：
  # 留着业务员能看见、能翻案，也是 AI 判例库的料（见 Crm::LeadScreenMemory）。
  # 界面上这类默认折叠，眼不见为净。
  def harvest_company(company, verdict)
    dup_id = existing_customer_id(company[:domain], company[:name])
    # 重跑时新结论要盖到已有线索上。模型不是每次都给同一个答案，不同步的话
    # 同一家公司底下会老行写「像买家」、新行写「不是」，自相矛盾。
    refresh_verdict(company, verdict)
    return skip_contacts(company, dup_id, verdict) if verdict&.dig(:verdict) == 'no'

    people = company[:domain].present? ? find_people(company[:domain]) : []
    return create_lead(company, nil, dup_id, verdict) if people.empty?

    # 上一轮没搜到人、建过一条「只有公司」的占位线索；这轮搜到人了就把占位清掉，
    # 否则同一家公司会出现一条没联系人的空行挨着几条正常线索。
    drop_placeholder(company[:domain])

    people.sum { |person| create_lead(company, person, dup_id, verdict) }
  end

  # 先找采购口，找不到再退一档找决策层。多出来的那次调用只发生在第一档落空时，
  # 而且搜索不扣 credits（扣的是后面人工点「解锁邮箱」那一步）。
  def find_people(domain)
    people = people_by_titles(domain, TARGET_TITLES)
    people.presence || people_by_titles(domain, FALLBACK_TITLES)
  end

  def people_by_titles(domain, titles)
    @client.search_people(domain: domain, titles: titles, limit: PEOPLE_PER_COMPANY)
           .select { |person| person[:has_email] }
  end

  # 这家公司是不是我们早就在跟的。搜出一堆自家客户是这类工具最常见的浪费，
  # 所以直接标出来，而不是让业务员自己去查重。
  def existing_customer_id(domain, company_name = nil)
    return nil if domain.blank? && company_name.blank?

    (@dup_finder ||= Crm::LeadDuplicate.new(account: @account))
      .find(domain: domain, company_name: company_name)&.customer_id
  end

  # 同一个人不重复建（按 apollo_person_id）。重跑任务时这条很关键。
  #
  # 碰到已有的那条不是什么都不做：公司资料（营收、电话、门店数）会变，
  # 重跑一次就该刷新一遍，否则存量线索永远停在第一次搜到时的样子。
  # 人工动过的部分（status / 建档关系 / 初筛结论 / 背调结果）一律不碰。
  def create_lead(company, person, dup_id, verdict = nil)
    attrs = lead_attrs(company, person, dup_id, verdict)
    scope = @account.crm_leads.where(crm_lead_campaign_id: @campaign.id)
    existing = person ? scope.find_by(apollo_person_id: person[:apollo_id]) : scope.find_by(domain: company[:domain], person_name: nil)
    return refresh_org(existing, attrs) if existing

    scope.create!(attrs)
    1
  rescue StandardError => e
    Rails.logger.warn("[LeadSearch] 建线索失败 #{company[:name]}: #{e.class} #{e.message}")
    0
  end

  # 只刷公司侧的事实，不动人工痕迹。返回 0——它不是「新找到的一条」。
  def refresh_org(lead, attrs)
    lead.update_columns( # rubocop:disable Rails/SkipsModelValidations
      industry: attrs[:industry] || lead.industry,
      country: attrs[:country] || lead.country,
      raw: attrs[:raw][:org] ? lead.raw.merge('org' => attrs[:raw][:org]) : lead.raw
    )
    0
  end

  # ⚠️ industry / city 别再指望 Apollo：搜索接口不返回这两个字段
  # （2026-11-07 实测 115 条线索 100% 为空）。行业改从 NAICS 代码翻过来，
  # 国家就是我们搜的那个市场——搜的时候限定了 organization_locations，本来就知道。
  def lead_attrs(company, person, dup_id, verdict = nil)
    {
      account_id: @account.id, status: 'FOUND',
      company_name: company[:name], domain: company[:domain],
      industry: Crm::NaicsLabel.for(company[:naics]),
      country: country_name(company[:market]),
      person_name: person&.dig(:name), title: person&.dig(:title),
      apollo_person_id: person&.dig(:apollo_id),
      dup_customer_id: dup_id,
      raw: { has_email: person&.dig(:has_email), matched_keyword: company[:matched_keyword],
             apollo_tag: company[:apollo_tag],
             market: company[:market], org: org_facts(company),
             screen: verdict&.dig(:verdict), screen_why: verdict&.dig(:why).presence,
             screen_score: verdict&.dig(:score) }.compact
    }
  end

  # 捞公司，顺带把「词表里查不到的词」记下来。
  def collect_companies
    collector = Crm::LeadCompanyCollector.new(campaign: @campaign, client: @client)
    companies = collector.call
    log_dead_keywords(collector.dead_keywords)
    companies
  end

  # Apollo 词表里不存在的搜索词。一条都搜不到不是 bug，是这个词本身在企业库里不存在
  # （"kids tablet"、"toy distributor" 都是这种）。记到任务的 last_error 里让人看见——
  # 不记的话这个词就永远静静地产出 0 条，没人知道为什么。
  def log_dead_keywords(dead)
    return if dead.blank?

    words = dead.pluck(:text).uniq
    Rails.logger.info("[Crm::LeadSearch] campaign #{@campaign.id} 词表里查不到: #{words.join('、')}")
    @campaign.update_columns(dead_keywords: words) # rubocop:disable Rails/SkipsModelValidations
  end

  # 搜索阶段白给的公司资料。这些不花 credits，但业务员判断时最想先看到：
  # 电话能直接打（比解锁邮箱便宜，解锁要花钱）、营收和门店数说明这家多大、
  # 上市代码基本等于「这是巨头，别指望直接对我们」。
  def org_facts(company)
    {
      # ⚠️ 要存 Apollo 给的**完整网址**，别只留主域名。
      # 有些站只在 www 上存在，裸域名连 DNS 记录都没有——
      # xploretech.com 查不到任何 A 记录，www.xploretech.com 才是活的。
      # 拿主域名硬拼 https:// 出来的链接，点进去就是「无法访问此网站」。
      'website' => company[:website],
      'phone' => company[:phone], 'linkedin' => company[:linkedin],
      'revenue' => company[:revenue], 'retail' => company[:retail_locations],
      'listed' => company[:listed], 'naics' => company[:naics].presence,
      'growth' => company[:headcount_growth]
    }.compact.presence
  end
end
