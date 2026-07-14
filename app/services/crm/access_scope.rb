# CRM 数据范围：给定账号内某成员，算出他能看到「哪些负责人的业务数据」。
# 口径：系统管理员看全部；主管看本人 + 所辖部门（含下级）全体成员；业务员/其他仅看本人。
# 主管的「团队」沿用组织部门负责人关系（Org::Department#leader_id），与 Org::DataScope 一致，
# 但按 crm_role 分支：恰好当部门负责人的业务员不会因此看到团队。
# 返回 :all 或可见的 user_id 数组（含自己）。
class Crm::AccessScope
  def initialize(account, account_user)
    @account = account
    @account_user = account_user
    @user_id = account_user&.user_id
  end

  def all_access?
    @account_user&.administrator? || false
  end

  def visible_owner_ids
    return :all if all_access?
    return [@user_id] unless @account_user&.crm_manager?

    led = @account.org_departments.where(leader_id: @user_id).pluck(:id)
    return [@user_id] if led.empty?

    dept_ids = Org::Department.subtree_ids(@account, led)
    member_ids = @account.org_memberships.where(department_id: dept_ids).pluck(:user_id)
    (member_ids + [@user_id]).uniq
  end
end
