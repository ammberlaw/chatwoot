class Api::V1::Accounts::AssignableAgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_inboxes

  def index
    agent_ids = @inboxes.map do |inbox|
      authorize inbox, :show?
      member_ids = inbox.members.pluck(:user_id)
      member_ids
    end
    agent_ids = agent_ids.inject(:&)
    agents = Current.account.users.where(id: agent_ids)
    # 个人 WhatsApp 收件箱只有机主一个成员，老板想把询盘派给业务员时下拉里无人可选。
    # 所以 CRM 成员一律可被指派；被指派人只看得到指派给他的那条会话，看不到该收件箱
    # 里的其他客户（见 Conversations::PermissionFilterService）。
    # 只放开这个下拉接口，自动分配仍按 inbox_members 轮询（见 InboxRoundRobinService）。
    @assignable_agents = (agents + crm_member_users + Current.account.administrators).uniq
  end

  private

  def crm_member_users
    ids = Current.account.account_users.select(&:can_access_crm?).map(&:user_id)
    Current.account.users.where(id: ids)
  end

  def fetch_inboxes
    @inboxes = Current.account.inboxes.find(permitted_params[:inbox_ids])
  end

  def permitted_params
    params.permit(inbox_ids: [])
  end
end
