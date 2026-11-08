class AddOwnerToCrmLeads < ActiveRecord::Migration[7.1]
  # 线索共享池：线索不再跟着任务的负责人走，而是**谁领谁得**。
  # owner_id 为空 = 还在池子里，谁都能看能领；领了起算 Crm::Lead::HOLD_DAYS 天保护期。
  def change
    add_column :crm_leads, :owner_id, :bigint
    add_column :crm_leads, :claimed_at, :datetime
    add_index :crm_leads, [:account_id, :owner_id]
  end
end
