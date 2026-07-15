# 成员邀请管理（HR·成员邀请，超级管理员与管理员）：生成/查看/作废邀请链接。
class Api::V1::Accounts::Crm::MemberInvitesController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_admin

  EXPIRES_DAYS = [7, 30].freeze

  def index
    @invites = Current.account.crm_member_invites
                      .includes(:department, :used_by)
                      .order(created_at: :desc)
  end

  def create
    # 防提权：管理员（deputy_admin）不可生成超级管理员邀请。
    if !Current.account_user.administrator? && params[:invite][:system_role].to_s == 'administrator'
      return render json: { error: '仅超级管理员可生成超级管理员邀请' }, status: :forbidden
    end

    @invite = Current.account.crm_member_invites.create!(invite_attrs)
    render :show
  end

  # 作废（未使用的直接删除；已使用的留档不允许删）。
  def destroy
    invite = Current.account.crm_member_invites.find(params[:id])
    return render json: { error: '已使用的邀请不可删除' }, status: :unprocessable_entity if invite.used_at.present?

    invite.destroy!
    head :ok
  end

  private

  def ensure_admin
    return if Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin?

    render json: { error: '仅超级管理员或管理员可管理成员邀请' }, status: :forbidden
  end

  def department_id_param
    id = params[:invite][:department_id].presence
    id && Current.account.org_departments.find(id).id
  end

  def invite_attrs
    days = params[:invite][:expires_days].to_i
    {
      system_role: params[:invite][:system_role].presence || 'sales',
      module_access: Array(params[:invite][:module_access]).map(&:to_s) & AccountUser::MODULES,
      department_id: department_id_param,
      note: params[:invite][:note].presence,
      created_by_id: current_user.id,
      expires_at: (EXPIRES_DAYS.include?(days) ? days : 7).days.from_now
    }
  end
end
