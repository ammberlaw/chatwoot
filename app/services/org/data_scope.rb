# 按部门授权：给定账号内某用户，算出他能看到「哪些人的业务数据」。
# 口径：管理员看全部；某部门负责人看本部门及所有下级部门全体成员的数据；
# 其余成员只看自己。返回 :all 或可见的 user_id 数组（含自己）。
class Org::DataScope
  def initialize(account, user, account_user)
    @account = account
    @user = user
    @account_user = account_user
  end

  def all_access?
    @account_user&.administrator? || false
  end

  def visible_user_ids
    return :all if all_access?

    led = @account.org_departments.where(leader_id: @user.id).pluck(:id)
    return [@user.id] if led.empty?

    dept_ids = Org::Department.subtree_ids(@account, led)
    member_ids = @account.org_memberships.where(department_id: dept_ids).pluck(:user_id)
    (member_ids + [@user.id]).uniq
  end
end
