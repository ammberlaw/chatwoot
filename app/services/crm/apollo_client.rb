# Apollo.io 企业数据库客户端：按域名补全公司概况（规模/成立/营收/行业/地址/领英/电话）。
# 用于客户 AI 背调——官网抓不到或信息稀薄时，Apollo 按域名直接返回结构化公司数据，补上「背调不到」的洞。
# 无 key 时静默降级（返回 nil），不阻断原有官网+AI 流程。
class Crm::ApolloClient
  # Apollo 账户的 credits 这个计费周期用完了。
  #
  # ⚠️ 必须和「这个人没有邮箱」分开报。混成一句「没解锁到邮箱」的话，
  # 业务员会以为是这条线索的问题，换一条再点——全公司额度为 0，换几百条都一样失败。
  # 2026-11-09 实测：余额 0 时所有搜索/解锁一律 HTTP 422。
  class CreditsExhausted < StandardError
    attr_reader :resume_on

    def initialize(resume_on = nil)
      @resume_on = resume_on
      super(message_for(resume_on))
    end

    private

    def message_for(resume_on)
      return '公司的 Apollo 额度已经用完，挖线索和解锁邮箱暂时都不可用。' if resume_on.blank?

      "公司的 Apollo 额度这个周期已经用完，#{resume_on} 恢复。" \
        '在那之前挖不了新线索、也解锁不了邮箱——已经挖到的线索照常领取、建档。'
    end
  end

  BASE_URL = 'https://api.apollo.io/api/v1'.freeze
  TIMEOUT = 8
  # 公司搜索失败最多试几次（见 post_search）。
  SEARCH_ATTEMPTS = 2

  def initialize(account:)
    @account = account
  end

  def configured?
    api_key.present?
  end

  # 公司概况：GET organizations/enrich?domain= 。返回规范化 Hash，查不到/未配 key 返回 nil。
  def organization(domain:)
    return if domain.blank? || !configured?

    resp = HTTParty.get("#{BASE_URL}/organizations/enrich",
                        query: { domain: domain },
                        headers: headers, timeout: TIMEOUT)
    org = resp.parsed_response.is_a?(Hash) ? resp.parsed_response['organization'] : nil
    normalize_org(org) if org.present?
  rescue StandardError => e
    Rails.logger.info("[Crm::Apollo] organization #{domain} failed: #{e.class} #{e.message}")
    nil
  end

  # 按公司名搜候选公司：POST mixed_companies/search 。返回 [{name, domain, industry, city, country}] 供用户挑选。
  # 名称常有歧义（同名多家），故只返回轻量候选，选中后再按域名 enrich。
  def search_organizations(name:, limit: 6)
    return [] if name.blank? || !configured?

    post_search({ q_organization_name: name, page: 1, per_page: limit }).select { |c| c[:domain].present? }
  end

  # 按国家 + 行业/产品关键词搜公司（展会找新买家用）：POST mixed_companies/search。
  # country 用英文国名（如 Germany）；keywords 是**一个或多个完整标签**，逗号分隔（别按空格拆，见 company_search_body）。
  def search_companies(country: nil, keywords: nil, limit: 25, employee_ranges: nil, page: 1)
    return [] unless configured?

    body = company_search_body(country, keywords, limit)
    return [] unless body

    # ⚠️ page 必须能往后翻。写死 1 的话一个关键词永远只有前 25 条，
    # 同一个任务重跑多少次都是同一批公司（2026-11-08 实测）。
    body[:page] = page

    # 规模过滤是关键：不加这个，搜「数字标牌采购」会搜出西门子、拜耳、SAP——
    # 全是巨头的集团采购，跟卖 $107 平板的我们完全不是一条线上的（2026-11-06 实测）。
    body[:organization_num_employees_ranges] = Array(employee_ranges) if employee_ranges.present?
    post_search(body).select { |c| c[:name].present? }
  end

  # 按公司域名搜联系人。**只返回预览**：名字半遮、没有邮箱，只有 has_email 告诉你有没有。
  # 拿真地址要再调 unlock_person（那一步才扣 credits）——Apollo 就是这么两段式设计的。
  #
  # ⚠️ 端点是 mixed_people/api_search，不是 mixed_people/search：
  # 后者对 API 调用方已经弃用，调了只会收到一句 deprecated。
  def search_people(domain:, titles: nil, limit: 5)
    return [] unless configured? && domain.present?

    body = { page: 1, per_page: limit, q_organization_domains_list: [domain] }
    body[:person_titles] = Array(titles) if titles.present?
    resp = HTTParty.post("#{BASE_URL}/mixed_people/api_search",
                         body: body.to_json, headers: headers, timeout: TIMEOUT)
    people = resp.parsed_response.is_a?(Hash) ? resp.parsed_response['people'] : nil
    Array(people).map { |person| normalize_person(person) }
  rescue StandardError => e
    Rails.logger.info("[Crm::Apollo] people search failed: #{e.class} #{e.message}")
    []
  end

  # 解锁一个联系人的真实邮箱。**这一步扣 credits**，所以只在人点了之后才调。
  def unlock_person(apollo_id)
    return nil unless configured? && apollo_id.present?

    resp = HTTParty.post("#{BASE_URL}/people/match",
                         body: { id: apollo_id }.to_json, headers: headers, timeout: TIMEOUT)
    raise_if_credits_exhausted!(resp)
    person = resp.parsed_response.is_a?(Hash) ? resp.parsed_response['person'] : nil
    person && unlocked_fields(person)
  rescue CreditsExhausted
    raise
  rescue StandardError => e
    Rails.logger.info("[Crm::Apollo] unlock failed: #{e.class} #{e.message}")
    nil
  end

  # 某个标签挂着多少家公司。给 Crm::ApolloTagResolver 探词表用——标签不存在就是 0。
  # 同样走搜索接口，**不扣 credits**。
  #
  # ⚠️ 探测失败（限流、超时）必须返回 **nil**，不能返回 0。
  # 两者对调用方的含义完全相反：0 = 这个词在词表里不存在，nil = 这次没问到。
  # 把限流当成 0 的话，调用方会把一个好词判成「词表里没有」，然后退到更短更糙的词去搜。
  def count_companies(tag:, country: nil)
    return nil unless configured?

    body = { page: 1, per_page: 1, q_organization_keyword_tags: [tag] }
    body[:organization_locations] = [country] if country.present?
    resp = HTTParty.post("#{BASE_URL}/mixed_companies/search",
                         body: body.to_json, headers: headers, timeout: TIMEOUT)
    raise_if_credits_exhausted!(resp)
    total = resp.parsed_response.is_a?(Hash) ? resp.parsed_response.dig('pagination', 'total_entries') : nil
    return total.to_i if total

    Rails.logger.info("[Crm::Apollo] count '#{tag}' 没问到: HTTP #{resp.code}")
    nil
  rescue CreditsExhausted
    raise
  rescue StandardError => e
    Rails.logger.info("[Crm::Apollo] count failed: #{e.class} #{e.message}")
    nil
  end

  private

  # 422 + BILLING.LIMIT.CREDITS_EXHAUSTED = 余额为 0，不是请求写错了。
  # 响应里带着下个计费周期的日期，一并带给调用方——
  # 只说「额度没了」，人还是要去 Apollo 后台翻什么时候恢复。
  def raise_if_credits_exhausted!(resp)
    return unless resp.code == 422

    details = resp.parsed_response.is_a?(Hash) ? resp.parsed_response['error_details'] : nil
    return unless details.is_a?(Hash) && details['code'] == 'BILLING.LIMIT.CREDITS_EXHAUSTED'

    raise CreditsExhausted, details.dig('context', 'next_billing_date', 'value')
  end

  # 搜索阶段拿得到的：名 + 遮住的姓 + 职位 + 有没有邮箱。
  def normalize_person(person)
    org = person['organization'] || {}
    {
      apollo_id: person['id'],
      name: [person['first_name'], person['last_name_obfuscated']].compact_blank.join(' '),
      title: person['title'],
      has_email: person['has_email'],
      company_name: org['name']
    }.compact
  end

  # 解锁之后才有的：真名、真邮箱、领英、公司官网。
  def unlocked_fields(person)
    org = person['organization'] || {}
    {
      name: person['name'], title: person['title'],
      email: person['email'], email_status: person['email_status'],
      linkedin_url: person['linkedin_url'],
      company_name: org['name'], domain: org['primary_domain'] || org['website_url']
    }.compact
  end

  # 拼公司搜索请求体（国家 + 关键词标签）；国家与关键词都空则返回 nil（不搜）。
  #
  # ⚠️ **只按逗号拆，绝不按空格拆。**
  # q_organization_keyword_tags 是一套固定词表，多个标签之间取并集。
  # 按空格拆的话 "consumer electronics brand" 会变成 consumer ∪ electronics ∪ brand，
  # 25196 家里一个买家都没有（广告代理、行业杂志、设计奖项）。
  # 整句搜不到就该交给 Crm::ApolloTagResolver 换个真实存在的标签，不是拆开来硬凑。
  def company_search_body(country, keywords, limit)
    tags = keywords.to_s.split(/[，,]/).map(&:strip).reject(&:blank?)
    return if country.blank? && tags.empty?

    body = { page: 1, per_page: limit }
    body[:organization_locations] = [country] if country.present?
    body[:q_organization_keyword_tags] = tags if tags.any?
    body
  end

  # POST mixed_companies/search，解析并规范化候选公司列表；异常静默返回 []。
  #
  # 失败重试一次：出国的连接会间歇性 Net::OpenTimeout / ReadTimeout，
  # 而拓客任务一次要搜几十页——一页超时就返回空，调用方会以为「这个关键词搜完了」
  # 直接停在这一页，一个好词整轮白费。重试一次能挡掉绝大部分抖动。
  def post_search(body)
    attempts = 0
    begin
      attempts += 1
      resp = HTTParty.post("#{BASE_URL}/mixed_companies/search",
                           body: body.to_json, headers: headers, timeout: TIMEOUT)
      # 余额为 0 不能当成「这次没搜到」吞掉：吞了就是整轮挖 0 条、任务显示正常结束，
      # 下一个人只会以为是关键词配错了（2026-11-09 就白排查了一轮）。重试也没意义。
      raise_if_credits_exhausted!(resp)
      orgs = resp.parsed_response.is_a?(Hash) ? resp.parsed_response['organizations'] : nil
      Array(orgs).map { |o| normalize_candidate(o) }
    rescue CreditsExhausted
      raise
    rescue StandardError => e
      Rails.logger.info("[Crm::Apollo] search failed (第 #{attempts} 次): #{e.class} #{e.message}")
      retry if attempts < SEARCH_ATTEMPTS

      []
    end
  end

  def headers
    { 'Content-Type' => 'application/json', 'Cache-Control' => 'no-cache', 'X-Api-Key' => api_key }
  end

  def api_key
    @api_key ||= Crm::AiSetting.for_account(@account).apollo_api_key.presence || ENV['APOLLO_API_KEY'].presence
  end

  def normalize_org(org)
    {
      name: org['name'],
      website: org['website_url'],
      linkedin: org['linkedin_url'],
      phone: org['phone'] || org.dig('primary_phone', 'number'),
      industry: org['industry'],
      founded_year: org['founded_year'],
      employees: org['estimated_num_employees'],
      revenue: org['annual_revenue_printed'],
      # 原始营收：0 与「没这个数」在界面上要区分开（annual_revenue_printed 两种情况都是空）
      revenue_raw: org['organization_revenue'],
      # 各部门人数：判断对方是贸易公司还是工厂、销售团队多大，比一个总人数有用
      departments: Array(org['departmental_head_count']).to_h.reject { |_k, v| v.to_i.zero? },
      languages: Array(org['languages']),
      retail_locations: org['retail_location_count'],
      country: org['country'],
      city: org['city'],
      address: org['raw_address'],
      description: org['short_description'] || org['seo_description'],
      keywords: Array(org['keywords']).first(8)
    }.compact
  end

  # 搜索阶段（mixed_companies/search）**不扣 credits**，但它返回的字段和
  # organization 那个接口不是一套：industry / city / country / estimated_num_employees
  # 这几个它根本不给（2026-11-07 实测 115 条线索这三列 100% 为空，不是数据缺，是问错了）。
  #
  # 下面这些才是它真给、而且白给的（98 家真实样本实测覆盖率）：
  #   linkedin 100% · naics 100% · website 89% · sic 85% · phone 71%
  #   revenue 53% · 人数增长 46% · 门店数 13% · 上市 3%
  # 电话尤其实用——解锁邮箱要花 credits，电话不要钱。
  def normalize_candidate(org)
    {
      name: org['name'],
      domain: org['primary_domain'],
      logo: org['logo_url'],
      apollo_org_id: org['id'],
      website: org['website_url'],
      linkedin: org['linkedin_url'],
      phone: org['phone'] || org.dig('primary_phone', 'number'),
      revenue: org['organization_revenue_printed'],
      # 门店数：卖广告机给连锁零售时，这个数就约等于订单量。
      # 0 和「没这个数」要分开，所以原样保留不 compact 掉。
      retail_locations: org['num_retail_locations'],
      # 行业代码：比 industry 字符串硬。实测德国几家杂志全是 513120（期刊出版），
      # 招聘公司是 561311/561320，而买家侧清一色 334xxx（电子制造）/423690（电子批发）。
      naics: Array(org['naics_codes']),
      sic: Array(org['sic_codes']),
      # 上市代码：有这个的基本是巨头，不是我们这档供应商直接对的买家。
      listed: org['publicly_traded_symbol'],
      headcount_growth: org['organization_headcount_twelve_month_growth']
    }.compact
  end
end
