# 业绩目标（按月）。对应 A-CRM(Twenty) salesTarget（CRM_SPEC §12.1）。
# target_order_count 语义为「目标新客户数」（字段名历史遗留）。
# 结转规则（未完成结转下月/超额顺延/每年清零）为展示层实时计算，S2 看板实现。
# == Schema Information
#
# Table name: crm_sales_targets
#
#  id                   :bigint           not null, primary key
#  name                 :string           not null
#  target_amount_micros :bigint
#  target_month         :datetime         not null
#  target_order_count   :integer
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  owner_id             :bigint
#
# Indexes
#
#  index_crm_sales_targets_on_account_id                   (account_id)
#  index_crm_sales_targets_on_account_id_and_target_month  (account_id,target_month)
#  index_crm_sales_targets_on_owner_id                     (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::SalesTarget < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  validates :name, presence: true
  validates :target_month, presence: true
  validates :target_month, uniqueness: { scope: [:account_id, :owner_id], message: '该业务员当月已有目标' }

  scope :for_month, ->(date) { where(target_month: date.beginning_of_month..date.end_of_month) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }

  before_validation :normalize_target_month

  private

  # 统一存月初，配合唯一性校验实现「一人一月一条」。
  def normalize_target_month
    self.target_month = target_month&.beginning_of_month
  end
end
