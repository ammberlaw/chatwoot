# 把一条线索建成客户档案。
#
# 查重走和建档页、AI 工具同一条路（Crm::Agent::Tools::CreateCustomer 的口径）：
# 撞到已有客户就不建、直接指过去——拓客最容易制造的就是重复档案。
class Crm::LeadToCustomer
  Result = Struct.new(:customer, :duplicate, keyword_init: true)

  # 建档落的客户分组 / 客户来源。两个类别下各有一条这个 code 的选项
  # （「客户设置」里能改显示名，code 别动）。缺了的话客户详情那两格会显示空白。
  LEAD_DEV_CODE = 'LEAD_DEV'.freeze

  # 线索的行业是 NAICS 翻出来的细类目（电子元器件批发、计算机外设制造…），
  # 客户档案的行业却是六选一的枚举，对不上就得翻译一道。
  #
  # 对不上的落 OTHER，不留空：「系统集成」「高等院校」这类确实会建档，但六个枚举里
  # 没有对应的格子——OTHER 的意思就是「以上都不是」，比留空更准确，留空看着像漏填了。
  INDUSTRY_ENUM = [
    [/分销|批发/, 'DISTRIBUTOR'],
    [/零售|门店/, 'RETAIL'],
    [/制造/, 'MANUFACTURING'],
    [/电商/, 'ECOMMERCE']
  ].freeze

  def self.call(lead, owner_id)
    account = lead.account
    existing = find_duplicate(account, lead)
    return claim(lead, existing, duplicate: true) if existing

    customer = account.crm_customers.create!(attrs_from(lead, owner_id))
    apply_labels(customer, lead)
    # 建档页做的那两件事一件不少（建联系人 + 补挂历史邮件），口径见 CreateCustomer 工具。
    customer.sync_contacts([{ email: lead.email, name: lead.person_name, is_primary: true }]) if lead.email.present?
    claim(lead, customer, duplicate: false)
  end

  def self.industry_enum(label)
    return nil if label.blank?

    INDUSTRY_ENUM.find { |pattern, _| pattern.match?(label) }&.last || 'OTHER'
  end

  BG_LINES = { 'note' => 'AI 判断', 'business' => '主营',
               'buying' => '可能采购', 'size' => '规模' }.freeze

  # 背调结果 → 客户档案上的 bg_summary / bg_checked_at
  #（这两列本来就有，一直只写不读；现在建档也往里写，客户详情页会显示）。
  def self.bg_attrs(lead)
    bg = lead.raw['bg']
    return {} unless bg.is_a?(Hash) && bg['status'] == 'ok'

    text = BG_LINES.filter_map { |key, label| bg[key].presence && "#{label}：#{bg[key]}" }.join("\n")
    return {} if text.blank?

    { bg_summary: text.truncate(2000), bg_checked_at: Time.current }
  end

  # 优先用 Apollo 给的完整网址：有些站只在 www 上存在，
  # 拿主域名拼出来的 https://xxx.com 根本打不开。
  def self.site_url(lead)
    Crm::SiteUrl.for(domain: lead.domain, website: lead.raw.dig('org', 'website'),
                     bg_url: lead.raw.dig('bg', 'url'))
  end

  # 搜索阶段白给的公司联系方式（见 Crm::ApolloClient#normalize_candidate）。
  def self.contact_attrs(lead)
    org = lead.raw['org'] || {}
    { contact_phone: org['phone'].presence, linkedin: org['linkedin'].presence }.compact
  end

  # 打两个标签：一个固定的「新客开发」用来圈出整批主动开发来的客户，
  # 一个任务名用来回溯「这个客户是哪一轮搜出来的」——效果表要靠它对账。
  SOURCE_LABEL = '新客开发'.freeze

  def self.apply_labels(customer, lead)
    names = [SOURCE_LABEL, lead.campaign&.name.presence].compact
                                                        .map { |n| n.to_s.strip.tr(' ', '-').first(40) }
    customer.label_list.add(names)
    customer.save!
  rescue StandardError => e
    # 标签打不上不该让建档失败——客户档案本身才是要紧的。
    Rails.logger.warn("[LeadToCustomer] 打标签失败 customer=#{customer.id}: #{e.class} #{e.message}")
  end

  # 线索上有什么就带什么。少带一项，业务员就得自己再查一遍。
  def self.attrs_from(lead, owner_id)
    {
      name: lead.company_name.to_s.truncate(120),
      contact_email: lead.email, primary_contact_name: lead.person_name,
      website: site_url(lead),
      trade_country: country_enum(lead.country),
      industry: industry_enum(lead.industry),
      # 来源和分组都钉在「新客开发」上——算这条线的投入产出全靠这两格，
      # 落进「其他」或者留空，建完就再也拆不出哪些客户是拓客来的了。
      source_channel: LEAD_DEV_CODE, customer_status: 'PROSPECT',
      # 任务上单配了分组就听任务的（个别任务要归去别处），没配才落「新客开发」。
      customer_group: lead.campaign&.default_customer_group.presence || LEAD_DEV_CODE,
      account_owner_id: owner_id, customer_remark: remark_for(lead)
    }.merge(contact_attrs(lead)).merge(bg_attrs(lead)).merge(vat_attrs(lead))
  end

  def self.find_duplicate(account, lead)
    by_email = lead.email.presence && account.crm_customers.find_by('LOWER(contact_email) = ?', lead.email.downcase)
    return by_email if by_email
    return nil if lead.domain.blank?

    account.crm_customers.where('LOWER(contact_email) LIKE ?', "%@#{lead.domain.downcase}").first
  end

  # 背调验过的欧盟税号带进客户档案——开 PI 做反向征税要用，
  # 省掉业务员发邮件问客户要的那几封。
  # ⚠️ **只带 VIES 说 valid 的**。这个号要印到形式发票上，没验过的宁可空着。
  def self.vat_attrs(lead)
    bg = lead.raw['bg'] || {}
    return {} unless bg['vat_status'] == 'valid' && bg['vat'].present?

    { vat_no: bg['vat'], vat_verified_at: Time.current }
  end

  # Apollo 给的是英文国家名（Germany），我们存的是枚举（GERMANY）。
  # 对不上就留空——国家不是必填，填个假的会把客户分布图带偏。
  def self.country_enum(name)
    key = name.to_s.strip.upcase.tr(' -', '__')
    Crm::Customer::COUNTRIES.include?(key) ? key : nil
  end

  def self.claim(lead, customer, duplicate:)
    lead.update!(status: 'CLAIMED', crm_customer_id: customer.id)
    Result.new(customer: customer, duplicate: duplicate)
  end

  # 把这条线索是怎么来的写进备注：哪个关键词搜到的、什么职位。
  # 业务员第一次联系时要靠这个开口。
  def self.remark_for(lead)
    bits = ["主动开发线索：#{lead.title}"].compact_blank
    kw = lead.raw['matched_keyword']
    bits << "搜索词「#{kw}」" if kw.present?
    bits << "行业 #{lead.industry}" if lead.industry.present?
    bits.join('；').presence
  end
end
