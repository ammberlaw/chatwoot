# 删掉「商机自动回收」的两个设置列。
#
# 这两列自建表起就没有任何读取方——没有任务在跑，设置页也没有入口，
# 是早期规格（A-CRM）留下的空壳。留着会让人以为后台有个商机回收在运行。
# 用户 2026-10-31 定：商机不单独回收，默认跟着客户跑（见 Crm::Customer#sync_opportunity_owner!）。
class DropOpportunityRecycleSettings < ActiveRecord::Migration[7.1]
  def up
    remove_column :crm_public_pool_settings, :opportunity_recycle_enabled
    remove_column :crm_public_pool_settings, :opportunity_stale_days
  end

  def down
    add_column :crm_public_pool_settings, :opportunity_recycle_enabled, :boolean, default: true, null: false
    add_column :crm_public_pool_settings, :opportunity_stale_days, :integer, default: 30, null: false
  end
end
