# Apollo.io 企业数据库客户端：按域名补全公司概况（规模/成立/营收/行业/地址/领英/电话）。
# 用于客户 AI 背调——官网抓不到或信息稀薄时，Apollo 按域名直接返回结构化公司数据，补上「背调不到」的洞。
# 无 key 时静默降级（返回 nil），不阻断原有官网+AI 流程。
class Crm::ApolloClient
  BASE_URL = 'https://api.apollo.io/api/v1'.freeze
  TIMEOUT = 8

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

    resp = HTTParty.post("#{BASE_URL}/mixed_companies/search",
                         body: { q_organization_name: name, page: 1, per_page: limit }.to_json,
                         headers: headers, timeout: TIMEOUT)
    orgs = resp.parsed_response.is_a?(Hash) ? resp.parsed_response['organizations'] : nil
    Array(orgs).map { |o| normalize_candidate(o) }.select { |c| c[:domain].present? }
  rescue StandardError => e
    Rails.logger.info("[Crm::Apollo] search #{name} failed: #{e.class} #{e.message}")
    []
  end

  private

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
      country: org['country'],
      city: org['city'],
      address: org['raw_address'],
      description: org['short_description'] || org['seo_description'],
      keywords: Array(org['keywords']).first(8)
    }.compact
  end

  def normalize_candidate(org)
    {
      name: org['name'],
      domain: org['primary_domain'],
      industry: org['industry'],
      city: org['city'],
      country: org['country'],
      logo: org['logo_url']
    }.compact
  end
end
