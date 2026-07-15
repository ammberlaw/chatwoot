class Api::V1::ProfilesController < Api::BaseController
  before_action :set_user

  def show; end

  def update
    if password_params[:password].present?
      # 密码自助仅限超级管理员/管理员/行政部门成员；其他成员由管理员在成员权限中重置。
      return render json: { error: '密码由管理员统一管理，请联系超级管理员或管理员重置' }, status: :forbidden unless @user.account_users.any?(&:password_self_service?)

      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  # 在线/离线状态由系统按实时连接判定，不允许成员手动设置。
  def auto_offline
    render json: { error: '在线状态由系统实时判定，不可手动设置' }, status: :forbidden
  end

  def availability
    render json: { error: '在线状态由系统实时判定，不可手动设置' }, status: :forbidden
  end

  def set_active_account
    @user.account_users.find_by(account_id: profile_params[:account_id]).update(active_at: Time.now.utc)
    head :ok
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  private

  def set_user
    @user = current_user
  end

  def profile_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      :account_id,
      ui_settings: {}
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
