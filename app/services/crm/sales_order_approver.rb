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

  def self.team_owner_ids(account_user)
    ids = Crm::AccessScope.new(account_user.account, account_user).team_visible_owner_ids
    ids == :all ? [] : ids
  end
  private_class_method :team_owner_ids
end
