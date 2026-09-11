# CRM「业务员」下拉统一数据源：只列 CRM 成员（can_access_crm，天然排除人事/财务/非CRM部门），
# 按调用者可见范围收口（业务员=自己，主管=本团队，管理员=全部）。
# 所有需要业务员下拉的板块共用，避免误用 /agents(全账号) 或 members#index(需管理权且含非CRM成员)。
# scope=team 时按 CRM 团队口径（销售订单用）；否则按部门口径（客户/商机等）。
class Api::V1::Accounts::Crm::AgentsController < Api::V1::Accounts::Crm::BaseController
  def index
    members = Current.account.account_users.includes(:user).select(&:can_access_crm?)
    members = participant_candidates(members) if params[:scope] == 'participants'
    members = scope_members(members) unless %w[all participants].include?(params[:scope])
    payload = members.sort_by { |m| m.user.name.to_s }
                     .map do |m|
      # thumbnail 给会话「对话参与者」的头像下拉用，其余下拉只取 id/name，多一个键无妨。
      { id: m.user_id, user_id: m.user_id, name: m.user.crm_display_name, thumbnail: m.user.avatar_url }
    end
    render json: { payload: payload }
  end

  private

  # 会话「对话参与者」下拉：业务员只能把主管/经理拉进自己的客户会话，不能拉平级业务员
  # ——否则互相加参与者就绕开了客户保护。主管及以上不受限，可以拉任意 CRM 成员。
  def participant_candidates(members)
    au = Current.account_user
    return members if au.administrator? || au.crm_deputy_admin? || au.crm_manager?

    members.select { |m| m.administrator? || m.crm_deputy_admin? || m.crm_manager? }
  end

  # scope=all 不收口（分配/转移目标：可指派给任意 CRM 成员）；
  # scope=team 按 CRM 团队口径（销售订单筛选）；否则按部门口径（客户/商机筛选）。
  def scope_members(members)
    ids = params[:scope] == 'team' ? crm_team_visible_owner_ids : crm_visible_owner_ids
    return members if ids == :all

    members.select { |m| ids.include?(m.user_id) }
  end
end
