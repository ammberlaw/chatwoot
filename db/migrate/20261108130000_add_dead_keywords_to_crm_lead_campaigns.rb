class AddDeadKeywordsToCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  # Apollo 词表里不存在的搜索词。词表是固定的，整句搜不到就是 0 条，
  # 跑完记在这里让人看见哪些词是白写的。
  def change
    add_column :crm_lead_campaigns, :dead_keywords, :jsonb, default: []
  end
end
