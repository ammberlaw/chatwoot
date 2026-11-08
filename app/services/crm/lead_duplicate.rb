# 这家公司是不是**已经有人在跟**的客户。
#
# 主动开发搜出一堆自家已有客户，是这类工具最常见的浪费；更糟的是业务员不知道，
# 照着发了开发信，撞到同事头上。所以不光要标出来，还要标**是谁的**。
#
# 口径比建档查重宽一点：那边是「要不要再建一条档」，这边是「要不要提醒人别碰」，
# 宁可多提醒一次，也别让两个人同时在跟同一家。
class Crm::LeadDuplicate
  Hit = Struct.new(:customer_id, :customer_name, :owner_name, keyword_init: true)

  def initialize(account:)
    @account = account
  end

  # domain 和公司名任一对上就算。
  # ⚠️ 只按联系邮箱的域名比是不够的：从小满迁过来的客户里有大量只填了网址没填邮箱，
  # 那批公司以前一条都标不出来（2026-11-08 用户反馈「要标出同事客户」时发现）。
  def find(domain:, company_name: nil)
    host = bare_host(domain)
    return nil if host.blank? && company_name.blank?

    customer = match(host, company_name)
    return nil if customer.nil?

    Hit.new(customer_id: customer.id, customer_name: customer.name,
            owner_name: customer.account_owner&.crm_display_name)
  end

  # 该藏起来的域名：**同事**还在保护期内持有的那些（见 Crm::Lead::HOLD_DAYS）。
  #
  # 用户要的是「同事已有的线索不显示」，不是标出来——标出来等于让人盯着一份
  # 自己碰不得的名单。搜索侧已经不会再捞重（全公司去重），这里处理的是
  # 去重上线之前积下的那批，以及同一家公司被两个人先后挖到的边角情况。
  #
  # 只藏**别人**的：同一个人自己几个任务里都有，那是他自己的事，不该藏。
  def held_by_others(domains, owner_id:, except_campaign_id:)
    hosts = Array(domains).filter_map { |d| bare_host(d) }.uniq
    return Set.new if hosts.empty? || owner_id.blank?

    @account.crm_leads.joins(:campaign).holding
            .where(domain: hosts)
            .where.not(crm_lead_campaign_id: except_campaign_id)
            .where.not(crm_lead_campaigns: { owner_id: [nil, owner_id] })
            .pluck(:domain).filter_map { |d| bare_host(d) }.to_set
  end

  # 一次把一整页线索的「是不是已有客户」查出来。返回 { 裸域名 => Hit }。
  #
  # 为什么在列表这一步现查、而不是只信搜索时存的 dup_customer_id：
  # 客户是同事**后来**才建的，那条线索就永远标不出来。撞单恰恰最容易发生在这种时候。
  def find_many(domains)
    hosts = Array(domains).filter_map { |d| bare_host(d) }.uniq
    return {} if hosts.empty?

    rows = @account.crm_customers.includes(:account_owner).where(
      "regexp_replace(regexp_replace(lower(coalesce(website, '')), '^https?://', ''), '^www\\.', '')
         ~ :hosts
       OR lower(coalesce(contact_email, '')) ~ :mails",
      hosts: "^(#{hosts.map { |h| Regexp.escape(h) }.join('|')})(/|$)",
      mails: "@(#{hosts.map { |h| Regexp.escape(h) }.join('|')})$"
    )
    index_by_host(rows, hosts)
  end

  private

  # 一个客户可能同时对上网址和邮箱，按域名归位即可。
  def index_by_host(rows, hosts)
    rows.each_with_object({}) do |customer, acc|
      host = hosts.find { |h| customer_host?(customer, h) }
      next if host.nil? || acc.key?(host)

      acc[host] = Hit.new(customer_id: customer.id, customer_name: customer.name,
                          owner_name: customer.account_owner&.crm_display_name)
    end
  end

  def customer_host?(customer, host)
    site = bare_host(customer.website)
    return true if site.present? && (site == host || site.start_with?("#{host}/"))

    customer.contact_email.to_s.downcase.end_with?("@#{host}")
  end

  def match(host, company_name)
    scope = @account.crm_customers.includes(:account_owner)
    by_host(scope, host) || by_name(scope, company_name)
  end

  # 网址和联系邮箱两条路。网址存的格式五花八门（有的带 https、有的带 www、有的带尾斜杠），
  # 所以比对前先在 SQL 里剥干净。
  def by_host(scope, host)
    return nil if host.blank?

    scope.where(
      "regexp_replace(regexp_replace(lower(coalesce(website, '')), '^https?://', ''), '^www\\.', '')
         LIKE :prefix
       OR lower(coalesce(contact_email, '')) LIKE :mail",
      prefix: "#{host}%", mail: "%@#{host}"
    ).first
  end

  # 公司名完全一样才算。模糊匹配会把「Box」和「Box Ltd」之外一堆不相干的也拉进来。
  def by_name(scope, company_name)
    return nil if company_name.blank?

    scope.where('lower(name) = ?', company_name.to_s.strip.downcase).first
  end

  def bare_host(domain)
    domain.to_s.strip.downcase.sub(%r{\Ahttps?://}, '').delete_prefix('www.').presence
  end
end
