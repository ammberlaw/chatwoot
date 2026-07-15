# 文档中心设置（单行）：show 全员可读（前端据此判断编辑权），update 仅管理员。
class Api::V1::Accounts::Crm::DocCenterSettingsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    @setting = Crm::DocCenterSetting.for_account(Current.account)
  end

  def update
    @setting = Crm::DocCenterSetting.for_account(Current.account)
    @setting.assign_attributes(setting_params)
    @setting.save!
    render :show
  end

  private

  def check_authorization
    authorize(Crm::DocCenterSetting)
  end

  def setting_params
    params.require(:setting).permit(:owner_id)
  end
end
