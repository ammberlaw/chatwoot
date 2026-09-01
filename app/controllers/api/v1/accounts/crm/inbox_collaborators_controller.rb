# 客服分配设置：管理各收件箱（如 WhatsApp）的协作者——即会话「分配客服代表」下拉里能选的人。
# 原生「设置 → 收件箱 → 协作者」页要 administrator 权限，副管理员进不去；这里放到 CRM 设置组，
# 超级管理员 + 副管理员可用，复用 Inbox#add_members/remove_members。
class Api::V1::Accounts::Crm::InboxCollaboratorsController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :ensure_admin

  # 收件箱 + 各自协作者，以及可选成员（账号内所有成员）。
  def index
    render json: {
      inboxes: Current.account.inboxes.order(:id).map do |inbox|
        { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, member_ids: inbox.members.pluck(:user_id) }
      end,
      candidates: Current.account.account_users.includes(:user).order('users.name').filter_map do |au|
        { id: au.user_id, name: au.user&.name, crm_role: au.crm_role } if au.user&.name.present?
      end
    }
  end

  # 覆盖某收件箱的协作者为传入的 user_ids（做增删差量）。
  def update
    inbox = Current.account.inboxes.find(params[:inbox_id])
    ids = Array(params[:user_ids]).map(&:to_i).uniq
    current = inbox.members.pluck(:user_id)
    inbox.add_members(ids - current)
    inbox.remove_members(current - ids)
    render json: { id: inbox.id, member_ids: inbox.reload.members.pluck(:user_id) }
  end

  private

  def ensure_admin
    return if admin_like?

    render json: { error: '仅超级管理员或副管理员可管理客服分配' }, status: :forbidden
  end

  def admin_like?
    Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin?
  end
end
