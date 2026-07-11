# 公海规则设置（每账户一行）。对应 A-CRM(Twenty) publicPoolSetting（CRM_SPEC §12.1）。
# 回收任务与私海上限守卫运行时读取；无记录时按默认值（90 天/启用/不回收从未跟进）。
# == Schema Information
#
# Table name: crm_public_pool_settings
#
#  id                         :bigint           not null, primary key
#  name                       :string           default("客户池规则")
#  pool_limit_key_account_won :integer
#  pool_limit_not_won         :integer
#  pool_limit_sample_won      :integer
#  pool_limit_social_media    :integer
#  pool_limit_won             :integer
#  recycle_enabled            :boolean          default(TRUE), not null
#  recycle_never_followed     :boolean          default(FALSE), not null
#  stale_days                 :integer          default(90), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#
# Indexes
#
#  index_crm_public_pool_settings_on_account_id  (account_id) UNIQUE
#
class Crm::PublicPoolSetting < ApplicationRecord
  belongs_to :account

  validates :account_id, uniqueness: true
  validates :stale_days, numericality: { greater_than: 0 }

  GROUP_LIMIT_FIELDS = {
    'KEY_ACCOUNT_WON' => :pool_limit_key_account_won,
    'WON' => :pool_limit_won,
    'SAMPLE_WON' => :pool_limit_sample_won,
    'NOT_WON' => :pool_limit_not_won,
    'SOCIAL_MEDIA' => :pool_limit_social_media
  }.freeze

  def self.for_account(account)
    find_by(account_id: account.id) || new(account: account)
  end

  # 分组私海上限；nil/<=0 = 不限。
  def limit_for_group(group)
    field = GROUP_LIMIT_FIELDS[group]
    field && public_send(field)
  end
end
