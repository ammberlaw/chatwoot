# 客户流转规则按分组细化：各客户分组可单独设置未跟进回收天数，
# 未设置的分组沿用全局 stale_days 默认值。
class AddGroupRecycleDaysToCrmPublicPoolSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_public_pool_settings, :recycle_days_key_account_won, :integer
    add_column :crm_public_pool_settings, :recycle_days_won, :integer
    add_column :crm_public_pool_settings, :recycle_days_sample_won, :integer
    add_column :crm_public_pool_settings, :recycle_days_not_won, :integer
    add_column :crm_public_pool_settings, :recycle_days_social_media, :integer
  end
end
