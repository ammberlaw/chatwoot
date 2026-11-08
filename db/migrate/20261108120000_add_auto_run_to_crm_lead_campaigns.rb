# 这个拓客任务要不要自动续挖。
#
# 手动按钮的问题是没人会天天去点。而关键词底下的公司是挖不完的——
# 加了翻页游标之后，连跑两次各新增两百多家全新公司（2026-11-08 实测）。
# 既然挖得动，就该让它自己挖，人只管看结果。
class AddAutoRunToCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_lead_campaigns, :auto_run, :boolean, null: false, default: false
    add_column :crm_lead_campaigns, :auto_run_at, :datetime
  end
end
