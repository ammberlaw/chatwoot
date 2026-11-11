# 跑一个拓客任务的搜索。自动续挖和将来的手动异步都走它。
#
# 挖完有新线索就通知负责人——不通知的话人不知道有新货，自动挖等于白挖。
class Crm::LeadSearchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(campaign_id)
    campaign = Crm::LeadCampaign.find_by(id: campaign_id)
    return if campaign.nil?

    created = 0
    learned = []
    campaign.with_search_lock do
      next unless campaign.claim_search!(job_id)

      created, learned = execute_search(campaign)
    end
    notify(campaign, created, learned) if created.positive?
  end

  private

  def execute_search(campaign)
    # 同一计划的自动续挖、手动搜索和重复投递都经过执行锁。
    learned = harvest_keywords(campaign)
    runner = Crm::LeadSearchRunner.new(campaign: campaign.reload)
    runner.call
    completed = campaign.finish_search!(job_id)
    campaign.update_columns(auto_run_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    [completed.fetch('created_leads'), learned]
  rescue StandardError => e
    error = runner ? runner.error_text(e).truncate(300) : '搜索任务执行失败，请重试'
    campaign.finish_search!(job_id, error: error)
    Rails.logger.error("[LeadSearch] execution failed campaign=#{campaign.id}: #{e.class}")
    [0, []]
  end

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
