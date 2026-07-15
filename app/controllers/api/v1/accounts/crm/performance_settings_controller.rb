# 绩效审批人设置：指定人事、总经理（仅管理员）。单记录。
class Api::V1::Accounts::Crm::PerformanceSettingsController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_admin

  def show
    @setting = Crm::PerformanceSetting.for_account(Current.account)
  end

  def update
    @setting = Crm::PerformanceSetting.for_account(Current.account)
    @setting.update!(setting_params)
    render 'show'
  end

  private

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: '仅管理员可设置' }, status: :forbidden
  end

  def setting_params
    params.require(:setting).permit(:hr_owner_id, :gm_owner_id,
                                    :scheme_visible_sales, :scheme_visible_manager,
                                    :sheet_visible_sales, :sheet_visible_manager)
  end
end
