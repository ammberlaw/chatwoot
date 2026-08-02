class AddClaimCooldown < ActiveRecord::Migration[7.1]
  def change
    # 客户进公海时记录原归属人，用于领回冷却期校验
    add_column :crm_customers, :previous_owner_id, :bigint
    # 原归属人领回冷却天数；0 = 不限制
    add_column :crm_public_pool_settings, :claim_cooldown_days, :integer, default: 30, null: false
  end
end
