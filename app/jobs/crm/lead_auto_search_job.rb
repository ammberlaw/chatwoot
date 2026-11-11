# 每天挑几个开了自动续挖的拓客任务，接着往下挖一层。
#
# 为什么要有：关键词底下的公司挖不完（加了翻页游标之后连跑两次各新增 235 家），
# 但手动按钮没人会天天点。挖得动就该让它自己挖，人只管看结果。
#
# ⚠️ **一个任务一个 job**。一次搜索要三四分钟（翻页 + 初筛 + 抓联系人），
# 几个任务串在一个 job 里会占着 scheduled_jobs 的线程十几分钟，
# 把后面的收信、提醒全堵住（2026-08 发信卡「发送中」就是这么来的）。
class Crm::LeadAutoSearchJob < ApplicationJob
  queue_as :scheduled_jobs

  # 一个任务两次自动挖之间至少隔这么久。挖太勤只会越挖越偏——
  # 相关性高的在前几页，翻到第 20 页基本是凑数的。
  MIN_INTERVAL = 3.days
  # 一天最多自动挖几个任务。不是为了省钱，是防任务多了之后一早上全在跑搜索。
  MAX_PER_DAY = 3

  def perform
    due_campaigns.each(&:enqueue_search!)
  end

  private

  def due_campaigns
    Crm::LeadCampaign.where(auto_run: true, status: %w[DONE PROFILED])
                     .where(auto_run_at: ..MIN_INTERVAL.ago)
                     .or(Crm::LeadCampaign.where(auto_run: true, status: %w[DONE PROFILED], auto_run_at: nil))
                     .order(Arel.sql('auto_run_at NULLS FIRST'))
                     .limit(MAX_PER_DAY)
  end
end
