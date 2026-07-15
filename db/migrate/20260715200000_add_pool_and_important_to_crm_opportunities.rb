# 商机公海 + 重要标记：
# - important 由业务员在编辑时标记，看板卡片高亮展示；
# - is_in_public_pool / public_pool_at 与客户公海同构，释放后全员可见可认领。
class AddPoolAndImportantToCrmOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_opportunities, :important, :boolean, default: false, null: false
    add_column :crm_opportunities, :is_in_public_pool, :boolean, default: false, null: false
    add_column :crm_opportunities, :public_pool_at, :datetime
    add_index :crm_opportunities, [:account_id, :is_in_public_pool]
  end
end
