# 给已有线索补上官网的业务邮箱。
#
# 为什么要单独一个 job、不直接重跑背调：背调跑过的线索 raw['bg'] 已经存在，
# Crm::LeadBgCheckJob 开头那句就把它跳过了；而且重跑会再花一次 AI token 去分析
# 已经分析过的官网，没必要。这里只抓官网 + 正则提邮箱，不调 AI、不碰 Apollo。
#
# ⚠️ 同背调：**一家公司一个 job**。一个 job 跑几十家会占着 Sidekiq 线程不放，
# 把收信和 WhatsApp 堵在后面。走 deferred，晚几分钟没人在意。
class Crm::LeadSiteContactJob < ApplicationJob
  queue_as :deferred

  def perform(lead_id)
    lead = Crm::Lead.find_by(id: lead_id)
    return unless needs_contacts?(lead)

    site = Crm::CompanySiteFetcher.new.call(lead.domain)
    return if site[:text].blank?

    contacts = Crm::SiteContactFinder.call(site, domain: lead.domain)
    stamp(lead, contacts) if contacts.emails.present? || contacts.contact_url.present?
  rescue StandardError => e
    Rails.logger.warn("[LeadSiteContact] lead=#{lead_id}: #{e.class} #{e.message}")
  end

  private

  def needs_contacts?(lead)
    lead.present? && lead.domain.present? && lead.reload.raw.dig('bg', 'emails').blank?
  end

  # 盖到同一家公司的每条线索上（口径同背调的 stamp）：
  # 一家公司几个联系人各一条线索，只写一条的话业务员点开另一条还是看不到邮箱。
  def stamp(lead, contacts)
    scope = lead.account.crm_leads.where(company_name: lead.company_name)
    scope.find_each do |row|
      bg = (row.raw['bg'] || {}).merge(
        'emails' => contacts.emails.presence, 'contact_url' => contacts.contact_url
      ).compact
      row.update_columns(raw: row.raw.merge('bg' => bg)) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
