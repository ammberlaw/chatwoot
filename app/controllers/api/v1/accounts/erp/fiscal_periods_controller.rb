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

  # 期末调汇：预览各外币科目的调汇差额（不落库）。
  def revaluation
    @revaluation = revaluation_service.preview(period: params[:period], rates: rate_params)
    render 'api/v1/accounts/erp/fiscal_periods/revaluation'
  rescue Erp::RevaluationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 生成调汇凭证（待过账）。
  def revalue
    @revaluation = revaluation_service.run!(period: params[:period], rates: rate_params)
    render 'api/v1/accounts/erp/fiscal_periods/revaluation'
  rescue Erp::RevaluationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 坏账计提：预览各客户按账龄段的计提额与需补提/转回的差额。
  def bad_debt
    @bad_debt = bad_debt_service.preview(period: params[:period], rates: params[:rates]&.permit!&.to_h)
    render 'api/v1/accounts/erp/fiscal_periods/bad_debt'
  rescue Erp::BadDebtService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 生成计提/转回凭证；带 rates 时同时把比例存成账套政策。
  def provision_bad_debt
    rates = params[:rates]&.permit!&.to_h
    bad_debt_service.save_rates!(rates) if rates.present?
    @bad_debt = bad_debt_service.run!(period: params[:period], rates: rates)
    render 'api/v1/accounts/erp/fiscal_periods/bad_debt'
  rescue Erp::BadDebtService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 年度结转：本年利润 → 利润分配，可选提取法定盈余公积。
  def year_end
    @year_end = year_end_service.preview(year: params[:year], surplus_rate: params[:surplus_rate].to_d)
    render 'api/v1/accounts/erp/fiscal_periods/year_end'
  rescue Erp::YearEndCloseService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def close_year
    @year_end = year_end_service.run!(year: params[:year], surplus_rate: params[:surplus_rate].to_d)
    render 'api/v1/accounts/erp/fiscal_periods/year_end'
  rescue Erp::YearEndCloseService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 反年结限管理员，与反结账同一把闸。
  def reopen_year
    return render json: { error: '反年结仅限管理员操作' }, status: :forbidden unless Current.account_user.administrator?

    @year_end = year_end_service.reopen!(year: params[:year]).merge(
      year_end_service.preview(year: params[:year])
    )
    render 'api/v1/accounts/erp/fiscal_periods/year_end'
  rescue Erp::YearEndCloseService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def year_end_service
    @year_end_service ||= Erp::YearEndCloseService.new(Current.account, current_user)
  end

  def bad_debt_service
    @bad_debt_service ||= Erp::BadDebtService.new(Current.account, current_user)
  end

  def revaluation_service
    @revaluation_service ||= Erp::RevaluationService.new(Current.account, current_user)
  end

  # rates 形如 { "USD" => "7.12" }；没填汇率时给空 hash，由 service 报「还没填汇率」。
  def rate_params
    params[:rates].present? ? params[:rates].permit!.to_h : {}
  end

  # 往来维度必须放行：应收/应付是往来科目，分录行强制要挂客户/供应商，
  # 不带过去的话期初里根本存不进应收应付（从金蝶导期初第一步就卡住）。
  def opening_rows
    Array(params[:rows]).map do |row|
      permitted = row.permit(:ledger_account_id, :debit_micros, :credit_micros, :exchange_rate,
                             :crm_customer_id, :mes_supplier_id)
      { ledger_account_id: permitted[:ledger_account_id], debit_micros: permitted[:debit_micros],
        credit_micros: permitted[:credit_micros], exchange_rate: permitted[:exchange_rate],
        crm_customer_id: permitted[:crm_customer_id], mes_supplier_id: permitted[:mes_supplier_id] }
    end
  end

  def check_authorization
    authorize(Erp::FiscalPeriod)
  end
end
