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

  # 期初建账：读当前期初凭证。
  def opening_balance
    @voucher = Erp::OpeningBalanceService.new(Current.account).current
    render 'api/v1/accounts/erp/fiscal_periods/opening_balance'
  end

  def save_opening_balance
    @voucher = Erp::OpeningBalanceService.new(Current.account, current_user).save!(
      rows: opening_rows, as_of: params[:as_of].presence || Time.zone.today
    )
    render 'api/v1/accounts/erp/fiscal_periods/opening_balance'
  rescue Erp::OpeningBalanceService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 两账对平：台账 vs 总账，结账前置检查。
  def reconciliation
    @rows = Erp::ReconciliationService.new(Current.account).call(
      as_of: params[:as_of].presence&.to_date || Time.zone.today
    )
    render 'api/v1/accounts/erp/fiscal_periods/reconciliation'
  end

  private

  def opening_rows
    Array(params[:rows]).map do |row|
      permitted = row.permit(:ledger_account_id, :debit_micros, :credit_micros, :exchange_rate)
      { ledger_account_id: permitted[:ledger_account_id], debit_micros: permitted[:debit_micros],
        credit_micros: permitted[:credit_micros], exchange_rate: permitted[:exchange_rate] }
    end
  end

  def check_authorization
    authorize(Erp::FiscalPeriod)
  end
end
