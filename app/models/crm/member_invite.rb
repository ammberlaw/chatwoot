# 成员邀请链接：管理员生成带预设角色/模块权限/部门的链接，新成员打开填写资料即加入。
# 一次性：使用后作废；到期自动失效。链接本身即凭证，加入的用户免邮件确认。
# == Schema Information
#
# Table name: crm_member_invites
#
#  id            :bigint           not null, primary key
#  expires_at    :datetime         not null
#  module_access :text             default(["crm", "erp", "mes"]), not null, is an Array
#  note          :string
#  system_role   :string           default("sales"), not null
#  token         :string           not null
#  used_at       :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#  department_id :bigint
#  used_by_id    :bigint
#
# Indexes
#
#  index_crm_member_invites_on_account_id  (account_id)
#  index_crm_member_invites_on_token       (token) UNIQUE
#
class Crm::MemberInvite < ApplicationRecord
  has_secure_token :token

  # 系统角色 → Chatwoot role + crm_role 映射（与成员权限页一致）。
  SYSTEM_ROLE_MAP = {
    'administrator' => [:administrator, nil],
    'deputy_admin' => [:agent, 'deputy_admin'],
    'manager' => [:agent, 'manager'],
    'sales' => [:agent, 'sales'],
    'hr' => [:agent, 'hr'], # 人事：组织/绩效/成员管理全套，无 CRM 销售数据
    'member' => [:agent, nil] # 普通成员：不进入 CRM，仅共享模块（OA/HR/协同/文档）
  }.freeze

  belongs_to :account
  belongs_to :department, class_name: 'Org::Department', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :used_by, class_name: 'User', optional: true

  validates :system_role, inclusion: { in: SYSTEM_ROLE_MAP.keys }

  def active?
    used_at.nil? && expires_at.future?
  end

  def status
    return 'used' if used_at.present?
    return 'expired' if expires_at.past?

    'pending'
  end

  # 按预设生成 account_user 属性。
  def account_user_attrs
    role, crm_role = SYSTEM_ROLE_MAP.fetch(system_role)
    { role: role, crm_role: crm_role, module_access: module_access, inviter_id: created_by_id }
  end
end
