# Apollo 返回的 JSON → 我们自己的字段名。
#
# 从 Crm::ApolloClient 拆出来：那边管「怎么调、调了几次、花了多少」，
# 这边只管「字段怎么对」。四个方法都是纯函数，不碰任何调用状态。
module Crm::ApolloNormalizer
  module_function

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
