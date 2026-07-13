# 部门成员：账号用户 ↔ 部门 的归属，带职位标题与「主负部门」标记。
# 一个用户可属于多个部门，其中最多一个为主负部门（is_primary）。
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
class Org::Membership < ApplicationRecord
  belongs_to :account
  belongs_to :department, class_name: 'Org::Department'
  belongs_to :user

  validates :user_id, uniqueness: { scope: :department_id }

  before_save :unset_other_primary, if: -> { is_primary? && (will_save_change_to_is_primary? || new_record?) }

  private

  # 一个用户只能有一个主负部门：设为主时把该用户其它主负标记清掉。
  def unset_other_primary
    Org::Membership.where(account_id: account_id, user_id: user_id, is_primary: true)
                   .where.not(id: id)
                   .update_all(is_primary: false) # rubocop:disable Rails/SkipsModelValidations
  end
end
