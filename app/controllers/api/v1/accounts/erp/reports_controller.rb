# 财务报表：资产负债表（时点）/ 利润表 / 现金流量表 / 科目余额表 / 试算平衡表（期间）/ 勾稽检查。只读，门禁走基类。
class Api::V1::Accounts::Erp::ReportsController < Api::V1::Accounts::Erp::BaseController
  def balance_sheet
    @report = report_service.balance_sheet(as_of: as_of_date)
  end

  def income_statement
    @report = report_service.income_statement(from: from_date, to: to_date)
  end

  def cash_flow
    @report = Erp::CashFlowService.new(Current.account).statement(from: from_date, to: to_date)
  end

  # 科目余额表：末级科目的期初/本期借贷/本年累计/期末（列口径对齐金蝶）。
  def account_balances
    @report = trial_service.account_balances(from: from_date, to: to_date)
  end

  # 试算平衡表：期初借贷/本期借贷/期末借贷 + 三对合计平衡校验。
  def trial_balance
    @report = trial_service.trial_balance(from: from_date, to: to_date)
  end

  # 勾稽检查：资产负债表与科目余额的对应关系，不平时点名是哪个科目掉出了报表。
  def tie_check
    @report = Erp::TieCheckService.new(Current.account).run(as_of: as_of_date)
  end

  # 现金流量项目字典（凭证录入时给现金分录挑项目用）。
  def cash_flow_items
    render json: { payload: Erp::CashFlowItem.items_for_select }
  end

  # 审计接口：把区间内的已记账数据打成 zip（科目表/序时簿/余额表/国标 XML）给事务所。
  def audit_export
    service = Erp::AuditExportService.new(Current.account)
    send_data service.export(from: from_date, to: to_date),
              filename: service.filename(from: from_date, to: to_date),
              type: 'application/zip'
  end

  private

  def report_service
    @report_service ||= Erp::FinancialReportService.new(Current.account)
  end

  def trial_service
    @trial_service ||= Erp::TrialBalanceService.new(Current.account)
  end

  def as_of_date
    params[:as_of].presence&.to_date || Time.zone.today.end_of_month
  end

  def from_date
    params[:from].presence&.to_date || Time.zone.today.beginning_of_month
  end

  def to_date
    params[:to].presence&.to_date || Time.zone.today.end_of_month
  end
end
