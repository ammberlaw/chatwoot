# 业务员自己给这个任务补的初筛条件。
#
# 为什么要有：通用标准不可能覆盖所有场景。比如「只要有自己门店的」「排掉纯线上代运营的」
# 「优先中东和北非」——这些只有跑业务的人知道，写死在 prompt 里既不合适也来不及。
class AddScreenCriteriaToCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_lead_campaigns, :screen_criteria, :text
  end
end
