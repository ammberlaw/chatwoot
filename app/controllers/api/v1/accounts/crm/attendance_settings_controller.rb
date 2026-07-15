# 考勤规则设置：工作日/上下班时间/宽限分钟（仅超级管理员与管理员）。
class Api::V1::Accounts::Crm::AttendanceSettingsController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :ensure_admin_like

  def show
    render json: setting_json
  end

  def update
    Crm::AttendanceSetting.for_account(Current.account).update!(setting_attrs)
    render json: setting_json
  end

  private

  def ensure_admin_like
    return if Current.account_user.administrator? || Current.account_user.crm_deputy_admin?

    render json: { error: '仅超级管理员或管理员可设置考勤规则' }, status: :forbidden
  end

  def setting_attrs
    {
      work_days: Array(params[:setting][:work_days]).map(&:to_i) & (1..7).to_a,
      clock_in_time: params[:setting][:clock_in_time],
      clock_out_time: params[:setting][:clock_out_time],
      grace_minutes: params[:setting][:grace_minutes].to_i,
      holidays: Array(params[:setting][:holidays]).map(&:to_s).grep(/\A\d{4}-\d{2}-\d{2}\z/).uniq.sort
    }
  end

  def setting_json
    setting = Crm::AttendanceSetting.for_account(Current.account)
    { work_days: setting.work_days, clock_in_time: setting.clock_in_time,
      clock_out_time: setting.clock_out_time, grace_minutes: setting.grace_minutes,
      holidays: setting.holidays }
  end
end
