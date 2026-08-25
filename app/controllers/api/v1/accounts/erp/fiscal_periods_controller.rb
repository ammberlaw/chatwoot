# 会计期间：期末结账 / 反结账 / 期间概览（结账向导）。
class Api::V1::Accounts::Erp::FiscalPeriodsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization

  def index
    @rows = Erp::PeriodCloseService.new(Current.account).overview(
      from_period: params[:from].presence || 12.months.ago.strftime('%Y-%m'),
      to_period: params[:to].presence || Time.zone.today.strftime('%Y-%m')
    )
  end

  def close
    @period = Erp::PeriodCloseService.new(Current.account, current_user).close!(params[:period])
    render 'api/v1/accounts/erp/fiscal_periods/show'
  rescue Erp::PeriodCloseService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 反结账限管理员（§13-6）。
  def reopen
    return render json: { error: '反结账仅限管理员操作' }, status: :forbidden unless Current.account_user.administrator?

    @period = Erp::PeriodCloseService.new(Current.account, current_user).reopen!(params[:period])
    render 'api/v1/accounts/erp/fiscal_periods/show'
  rescue Erp::PeriodCloseService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize(Erp::FiscalPeriod)
  end
end
