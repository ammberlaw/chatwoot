class AddSharedToCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  # 这个任务挖到的线索要不要进共享池。
  # 默认进（整套机制就是为共享设计的）；不勾的任务，线索只有负责人看得见、领得走。
  def change
    add_column :crm_lead_campaigns, :shared, :boolean, default: true, null: false
  end
end
