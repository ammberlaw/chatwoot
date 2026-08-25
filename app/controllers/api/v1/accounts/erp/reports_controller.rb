# 财务报表：资产负债表（时点）/ 利润表（期间）。只读，门禁走基类。
class Api::V1::Accounts::Erp::ReportsController < Api::V1::Accounts::Erp::BaseController
  def balance_sheet
    @report = report_service.balance_sheet(as_of: as_of_date)
  end

  def income_statement
    @report = report_service.income_statement(from: from_date, to: to_date)
  end

  private

  def report_service
    @report_service ||= Erp::FinancialReportService.new(Current.account)
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
