# 客服分配设置：管理各收件箱（如 WhatsApp）的协作者——即会话「分配客服代表」下拉里能选的人。
# 原生「设置 → 收件箱 → 协作者」页要 administrator 权限，副管理员进不去；这里放到 CRM 设置组，
# 超级管理员 + 副管理员可用，复用 Inbox#add_members/remove_members。
class Api::V1::Accounts::Crm::InboxCollaboratorsController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :ensure_admin

  # 收件箱 + 各自协作者，以及可选成员。
  def index
    inboxes = Current.account.inboxes.order(:id).map do |inbox|
      { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, member_ids: inbox.members.pluck(:user_id) }
    end
    render json: {
      inboxes: inboxes,
      candidates: candidate_members(inboxes.flat_map { |ib| ib[:member_ids] }.uniq).map do |au|
        { id: au.user_id, name: au.user.name, crm_role: au.crm_role }
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

  # 可选成员：在职的 CRM 成员（口径见 AccountUser#can_access_crm?）。会话是业务在跟，
  # 车间、仓管、质检这些岗位从不接客户消息，摆进来只是让人在四十来个名字里找人更费劲。
  # 已经挂在收件箱上的人一律留着（哪怕不是 CRM 成员、哪怕已离职）——名单藏了人，
  # 「已选 N 人」就对不上，全选还会把看不见的人顺手摘掉。
  def candidate_members(assigned_user_ids)
    Current.account.account_users.includes(:user).order('users.name').select do |au|
      next false if au.user&.name.blank?

      assigned_user_ids.include?(au.user_id) ||
        (au.deactivated_at.nil? && au.can_access_crm?)
    end
  end

  def ensure_admin
    return if admin_like?

    render json: { error: '仅超级管理员或副管理员可管理客服分配' }, status: :forbidden
  end

  def admin_like?
    Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin?
  end
end
