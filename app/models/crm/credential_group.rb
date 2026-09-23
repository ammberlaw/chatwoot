# 账号密码分组：既是归类，也是授权单元。
# viewer_ids 空 = 只有管理员/副管能看（与文档板块「空=全员可见」相反——密码默认收紧）。
# == Schema Information
#
# Table name: crm_credential_groups
#
#  id          :bigint           not null, primary key
#  manager_ids :bigint           default([]), not null, is an Array
#  name        :string           not null
#  position    :integer          default(0), not null
#  viewer_ids  :bigint           default([]), not null, is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  idx_crm_cred_groups_name                   (account_id,name) UNIQUE
#  index_crm_credential_groups_on_account_id  (account_id)
#
class Crm::CredentialGroup < ApplicationRecord
  self.table_name = 'crm_credential_groups'

  DEFAULT_GROUPS = %w[平台账号 邮箱账号 服务器与域名 银行与支付 其他].freeze

  belongs_to :account
  has_many :credentials, class_name: 'Crm::Credential', foreign_key: :crm_credential_group_id,
                         inverse_of: :group, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :ordered, -> { order(:position, :id) }

  def viewer?(user_id)
    viewer_ids.include?(user_id) || manager_ids.include?(user_id)
  end

  # 可维护（增删改本组账号）：组内负责人。管理员/副管在控制器层直通。
  def manager?(user_id)
    manager_ids.include?(user_id)
  end

  def viewers = User.where(id: viewer_ids)
  def managers = User.where(id: manager_ids)

  # 首次进入时建一套默认分组；之后被删掉的不再自动重建（同文档板块的做法）。
  def self.ensure_defaults!(account)
    return if account.crm_credential_groups.exists?

    DEFAULT_GROUPS.each_with_index do |name, index|
      account.crm_credential_groups.create!(name: name, position: index)
    end
  end
end
