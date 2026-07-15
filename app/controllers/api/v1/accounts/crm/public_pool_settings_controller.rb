# 公海规则设置（单行）：show 返回当前（无记录返回默认值），update 创建或更新。
class Api::V1::Accounts::Crm::PublicPoolSettingsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    @setting = Crm::PublicPoolSetting.for_account(Current.account)
  end

  def update
    @setting = Crm::PublicPoolSetting.for_account(Current.account)
    @setting.assign_attributes(setting_params)
    @setting.save!
    render :show
  end

  private

  def check_authorization
    authorize(Crm::PublicPoolSetting)
  end

  def setting_params
    params.require(:setting).permit(
      :name, :stale_days, :recycle_enabled, :recycle_never_followed,
      :pool_limit_key_account_won, :pool_limit_won, :pool_limit_sample_won,
      :pool_limit_not_won, :pool_limit_social_media,
      :recycle_days_key_account_won, :recycle_days_won, :recycle_days_sample_won,
      :recycle_days_not_won, :recycle_days_social_media
    )
  end
end
