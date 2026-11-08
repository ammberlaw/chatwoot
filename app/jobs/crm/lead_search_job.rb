# 跑一个拓客任务的搜索。自动续挖和将来的手动异步都走它。
#
# 挖完有新线索就通知负责人——不通知的话人不知道有新货，自动挖等于白挖。
class Crm::LeadSearchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(campaign_id)
    campaign = Crm::LeadCampaign.find_by(id: campaign_id)
    return if campaign.nil? || campaign.keywords.blank?

    # 先从认可的公司身上学几个新词，再搜。
    # 只翻页的话挖到第 7 页平均匹配度掉到 15（2026-11-08 实测）——
    # 要续的是关键词，不是页码。学不到就按原词搜，不影响主流程。
    learned = harvest_keywords(campaign)
    created = Crm::LeadSearchRunner.new(campaign: campaign.reload).call
    campaign.update_columns(auto_run_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    notify(campaign, created, learned) if created.positive?
  end

  private

  def harvest_keywords(campaign)
    Crm::LeadKeywordHarvester.new(campaign: campaign).call
  rescue StandardError => e
    Rails.logger.warn("[LeadSearch] 学关键词失败 campaign=#{campaign.id}: #{e.class} #{e.message}")
    []
  end

  # 只报「像买家」的那几条，不报总数——总数里大半是会被折叠的噪音，
  # 报出来只会让人觉得这提醒没用。
  #
  # 正文交给 Crm::LeadDigest 写：光列名单，业务员还是不知道先打哪家、凭什么，
  # 那份名单他在页面上也能翻，通知等于没帮上忙。AI 写不出来会自动退回机械版。
  def notify(campaign, created, learned = [])
    account = campaign.account
    owner_id = campaign.owner_id
    return if owner_id.blank?

    body = Crm::LeadDigest.new(campaign: campaign, created: created, learned: learned).call
    return if body.blank?

    Chat::NotifyService.new(account: account, sender: Crm::SystemUser.for(account))
                       .notify(owner_id, body, ref: { type: 'lead_campaign', id: campaign.id })
  end
end
