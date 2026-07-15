# 成员邀请公开端点：凭 token 查看邀请信息 / 填资料加入（未登录可访问）。
class Public::Api::V1::MemberInvitesController < PublicController
  before_action :fetch_invite

  def show
    render json: {
      account_name: @invite.account.name,
      status: @invite.status,
      note: @invite.note
    }
  end

  # 链接即凭证：创建用户（免邮件确认）并按预设角色/模块/部门加入账号。
  def accept
    return render json: { error: '邀请已失效' }, status: :unprocessable_entity unless @invite.active?
    return render json: { error: '该邮箱已注册，请联系管理员在成员权限中直接添加' }, status: :unprocessable_entity if email_taken?

    user = nil
    ActiveRecord::Base.transaction do
      user = build_user
      @invite.account.account_users.create!(@invite.account_user_attrs.merge(user_id: user.id))
      create_membership(user)
      @invite.update!(used_at: Time.current, used_by_id: user.id)
    end
    render json: { email: user.email, account_name: @invite.account.name }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join('；') }, status: :unprocessable_entity
  end

  private

  def fetch_invite
    @invite = Crm::MemberInvite.find_by!(token: params[:token])
  end

  def email_taken?
    User.exists?(email: params[:email].to_s.downcase)
  end

  def build_user
    user = User.new(name: params[:name], email: params[:email],
                    password: params[:password], password_confirmation: params[:password])
    user.skip_confirmation!
    user.save!
    user
  end

  def create_membership(user)
    return if @invite.department_id.blank?

    Org::Membership.create!(account_id: @invite.account_id, department_id: @invite.department_id,
                            user_id: user.id, is_primary: true)
  end
end
