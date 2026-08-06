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
    @account_user&.administrator? || @account_user&.crm_deputy_admin? || false
  end

  def visible_owner_ids
    return :all if all_access?

    team_owner_ids
  end

  # 邮件专用口径：邮件是私人往来通信。系统管理员（老板）看全员；
  # 「CRM 团队」负责人看本团队（自己 + 团队成员）；其余（含副管理员、普通业务员）只看自己。
  # 刻意用 CRM 团队（crm_teams.team_lead_id + account_users.crm_team_id），
  # 不用 HR 组织部门——与业务数据 visible_owner_ids（按部门）口径不同。
  def mail_visible_owner_ids
    return :all if @account_user&.administrator?

    led_team_ids = @account.crm_teams.where(team_lead_id: @user_id).pluck(:id)
    return [@user_id] if led_team_ids.empty?

    member_ids = @account.account_users.where(crm_team_id: led_team_ids).pluck(:user_id)
    (member_ids + [@user_id]).uniq
  end

  private

  # 按部门负责人关系算团队：带团队者看「本部门（含下级）全员 + 自己」，否则只看自己。
  def team_owner_ids
    return [@user_id] unless @account_user&.crm_manager?

    led = @account.org_departments.where(leader_id: @user_id).pluck(:id)
    return [@user_id] if led.empty?

    dept_ids = Org::Department.subtree_ids(@account, led)
    member_ids = @account.org_memberships.where(department_id: dept_ids).pluck(:user_id)
    (member_ids + [@user_id]).uniq
  end
end
