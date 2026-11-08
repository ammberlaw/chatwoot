# 线索一键背调：拿线索的域名去跑客户 AI 背调（抓官网 + Apollo 企业库），
# 把结果压成几句话存回线索。
#
# 为什么要存：一次背调十几秒、还要走一次 Apollo，而线索池一屏就十条。
# 存下来之后再进页面直接看得见，不用重跑。
#
# 同一家公司名下的几个联系人共用一份结果（DATA MODUL AG 这种一搜就是好几个采购），
# 口径同 Crm::LeadScreener 的判定写回。
class Crm::LeadBackgroundCheck
  # 存进 raw 的几个字段都掐短——线索池是扫一眼就要做决定的地方，
  # 真要看全的点「完整背调」去背调页。
  SUMMARY_MAX = 220

  def initialize(lead:)
    @lead = lead
    @account = lead.account
  end

  # 返回存回去的那份摘要（Hash），查不出来也返回，附上 status 让前端说人话。
  def call
    return { 'status' => 'no_domain' } if @lead.domain.blank?

    result = Crm::CompanyLookupService.new(account: @account).call(query: @lead.domain)
    digest = digest_for(result)
    stamp(digest)
    digest
  end

  private

  def digest_for(result)
    profile = result[:profile] || {}
    {
      'status' => result[:status].to_s,
      'url' => result[:url],
      # 官网的 HTTP 状态。451 是地区封锁、403 是反爬——这两种业务员点进去同样打不开，
      # 列表上提前标出来，省得白点一次（2026-11-08 toysrus.es 就是 451）。
      'site_status' => result[:site_status],
      'business' => clip(profile['business']),
      'buying' => clip(profile['buying_categories']),
      'size' => clip(profile['size_hint']),
      'legit' => profile['legit'],
      'note' => clip(profile['note']),
      'employees' => result.dig(:enrichment, :employees),
      # 欧盟官方税号验证：三方证据里唯一官方的那一方。
      # 验不过的也存——官网印着个验不过的号，比查不到更该让人看见。
      'vat' => result.dig(:vat, :number), 'vat_status' => result.dig(:vat, :status),
      # 意大利这类成员国连官方注册名都给，可以和官网的说法对账（德国不给）。
      'vat_name' => clip(result.dig(:vat, :name)),
      'checked_at' => Time.current.iso8601
    }.compact
  end

  # 「未提及」是模型按 prompt 要求填的占位，存下来只会占着位置误导人。
  def clip(value)
    text = value.to_s.strip
    return nil if text.blank? || text == '未提及'

    text.truncate(SUMMARY_MAX)
  end

  # 同一家公司的所有线索一起盖章。没公司名的（极少）只盖自己这条。
  def stamp(digest)
    scope = @account.crm_leads.where(crm_lead_campaign_id: @lead.crm_lead_campaign_id)
    scope = @lead.company_name.present? ? scope.where(company_name: @lead.company_name) : scope.where(id: @lead.id)
    scope.find_each do |lead|
      lead.update_columns(raw: lead.raw.merge('bg' => digest)) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
