# 谁能审这张销售订单。
#
# 控制器（挡写）和 jbuilder（决定前端显不显示「通过/驳回」）都要问同一个问题，
# 所以收在这一处——两边各写一份的话，迟早出现「按钮看得见、点下去 403」。
#
# 口径：管理员/副管恒可审；其余要是**这张单业务员所在 CRM 团队的负责人**。
# 团队负责人自己建的单没有更上一级可批，落到管理员/副管手里——否则主管的单
# 会永远卡在待审核，他自己也转不了。
class Crm::SalesOrderApprover
  # order 为 nil 时问的是「这个人有没有审核身份」（建单时用来决定新单落不落待审核）。
  def self.can?(account_user, order = nil)
    return false unless account_user
    return true if account_user.administrator? || account_user.crm_deputy_admin?
    return false unless account_user.crm_team_lead?
    return true if order.nil?

    order.owner_id != account_user.user_id && team_owner_ids(account_user).include?(order.owner_id)
  end

  # 等我审的单（侧栏角标 / 列表「待我审」页签）。与 can? 同一口径——
  # 角标显示 3、点进去只有 1 的话，角标就没人信了。
  def self.pending_scope(account, account_user)
    scope = account.crm_sales_orders.where(approval_status: 'PENDING')
    return scope.none unless account_user
    return scope if account_user.administrator? || account_user.crm_deputy_admin?
    return scope.none unless account_user.crm_team_lead?

    scope.where(owner_id: team_owner_ids(account_user) - [account_user.user_id])
  end

  # 这张单该提醒谁去审。优先该业务员所在团队的负责人；团队没设负责人、或负责人
  # 就是业务员本人（审不了自己的单）时落到管理员/副管——不然单子挂在那儿没人知道，
  # 只能等业务员开口问。
  def self.notify_ids(account, order)
    lead_id = team_lead_id_for(account, order.owner_id)
    return [lead_id] if lead_id.present? && lead_id != order.owner_id

    admin_like_ids(account)
  end

  def self.team_owner_ids(account_user)
    ids = Crm::AccessScope.new(account_user.account, account_user).team_visible_owner_ids
    ids == :all ? [] : ids
  end
  private_class_method :team_owner_ids

  # 业务员所在 CRM 团队的负责人（团队归属存在 account_users.crm_team_id）。
  def self.team_lead_id_for(account, owner_id)
    return nil if owner_id.blank?

    team_id = account.account_users.where(user_id: owner_id).pick(:crm_team_id)
    return nil if team_id.blank?

    account.crm_teams.where(id: team_id).pick(:team_lead_id)
  end
  private_class_method :team_lead_id_for

  def self.admin_like_ids(account)
    account.account_users
           .where(role: :administrator)
           .or(account.account_users.where(crm_role: 'deputy_admin'))
           .pluck(:user_id)
  end
  private_class_method :admin_like_ids
end
