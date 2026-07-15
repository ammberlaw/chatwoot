# 商机流转规则：与客户公海同机制——超过 N 天无任何更新（编辑/推进）的
# 在管商机自动流入商机公海；已成交/输单终态不回收。
class AddOpportunityRecycleToCrmPublicPoolSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_public_pool_settings, :opportunity_recycle_enabled, :boolean, default: true, null: false
    add_column :crm_public_pool_settings, :opportunity_stale_days, :integer, default: 30, null: false
  end
end
