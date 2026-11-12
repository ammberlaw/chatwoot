# 部门成员：账号用户 ↔ 部门 的归属，带职位标题与「归属部门」标记。
# 一个用户可属于多个部门，其中最多一个为归属部门（is_primary）。
# == Schema Information
#
# Table name: org_memberships
#
#  id            :bigint           not null, primary key
#  is_primary    :boolean          default(FALSE), not null
#  title         :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  department_id :bigint           not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_org_memberships_on_account_id     (account_id)
#  index_org_memberships_on_department_id  (department_id)
#  index_org_memberships_on_user_id        (user_id)
#  index_org_memberships_unique            (department_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (department_id => org_departments.id) ON DELETE => cascade
#
class Org::Membership < ApplicationRecord
  belongs_to :account
  belongs_to :department, class_name: 'Org::Department'
  belongs_to :user

  validates :user_id, uniqueness: { scope: :department_id }

  attr_accessor :skip_employee_sync
  validate do
    errors.add(:department_id, '部门不存在、已停用或不属于当前公司') unless account.org_departments.active.exists?(id: department_id)
    errors.add(:user_id, '必须选择当前公司在职成员') unless account.account_users.active_members.exists?(user_id: user_id)
  end
  after_save { Org::PersonnelSync.from_membership(self) }
  after_destroy { Org::PersonnelSync.from_membership(self, removed: true) if is_primary? }
  after_save :record_org_change
  after_destroy :record_org_removal

  before_save :unset_other_primary, if: -> { is_primary? && (will_save_change_to_is_primary? || new_record?) }

  private

  def record_org_change
    Crm::HrEvent.record!(account: account, department: department, user_id: user_id, kind: 'org_member_changed',
                        payload: { department_name: department.name, user_name: user.crm_display_name, title: title, is_primary: is_primary })
  end

  def record_org_removal
    Crm::HrEvent.record!(account: account, department: department, user_id: user_id, kind: 'org_member_removed',
                        payload: { department_name: department.name, user_name: user.crm_display_name })
  end

  # 一个用户只能有一个归属部门：设为主时把该用户其它归属标记清掉。
  def unset_other_primary
    Org::Membership.where(account_id: account_id, user_id: user_id, is_primary: true)
                   .where.not(id: id)
                   .update_all(is_primary: false) # rubocop:disable Rails/SkipsModelValidations
  end
end
