# 文档中心设置（每账户一行）：owner = 文档中心负责人。
# 管理员与负责人可上传/编辑/删除文档中心（GENERAL 库）的公司文档，其余成员只读。
# == Schema Information
#
# Table name: crm_doc_center_settings
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  owner_id   :bigint
#
# Indexes
#
#  index_crm_doc_center_settings_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::DocCenterSetting < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  validates :account_id, uniqueness: true

  def self.for_account(account)
    find_by(account_id: account.id) || new(account: account)
  end
end
