# 背调跑完之后重判初筛分数（见 Crm::LeadRescreen）。
#
# 为什么要单独一个 job、还要自己续：背调是一家公司一个 job 排在 deferred 队列上，
# 一轮六十家要跑十几二十分钟。搜索结束时立刻重判只能判到最先跑完的那几家，
# 所以这个 job 跑完一轮，如果还有背调在路上，就隔几分钟再来一趟。
class Crm::LeadRescreenJob < ApplicationJob
  # 和背调同队列：它本来就是跟在背调屁股后面的收尾动作，不该去抢业务队列。
  queue_as :deferred

  # 最多续几轮。防背调那边一直有残留时这个 job 无限续下去。
  MAX_ROUNDS = 8
  WAIT = 4.minutes

  def perform(campaign_id, round = 1)
    campaign = Crm::LeadCampaign.find_by(id: campaign_id)
    return if campaign.nil?

    result = Crm::LeadRescreen.new(campaign: campaign).call
    log(campaign, round, result)
    requeue(campaign, round)
  end

  private

  def log(campaign, round, result)
    return if result[:judged].zero?

    Rails.logger.info("[LeadRescreen] campaign=#{campaign.id} 第#{round}轮：" \
                      "重判 #{result[:judged]} 家，降级 #{result[:downgraded]} 家")
  end

  # 还有背调在跑、或还有没重判过的，就再来一趟。
  def requeue(campaign, round)
    return if round >= MAX_ROUNDS
    return unless more_coming?(campaign)

    Crm::LeadRescreenJob.set(wait: WAIT).perform_later(campaign.id, round + 1)
  end

  def more_coming?(campaign)
    scope = campaign.account.crm_leads.where(crm_lead_campaign_id: campaign.id)
    scope.where("raw ? 'bg_running_at'").exists? ||
      Crm::LeadRescreen.new(campaign: campaign).pending.exists?
  end
end
