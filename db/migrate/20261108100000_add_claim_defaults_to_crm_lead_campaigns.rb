# 这个拓客任务建出来的客户，默认进哪个分组。
#
# 为什么挂在任务上而不是做成全局设置：不同任务开发的是不同产品、不同市场，
# 平板那批和广告机那批本来就该分开看。做成全局的话，第二个任务一来就不够用了。
class AddClaimDefaultsToCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_lead_campaigns, :default_customer_group, :string
  end
end
