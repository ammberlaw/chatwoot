# 账簿：科目余额表 / 明细账 / 维度明细账。全部实时按 POSTED 凭证算，不落中间表。
# 期间默认取本月；日期以凭证日期为准。
class Api::V1::Accounts::Erp::LedgersController < Api::V1::Accounts::Erp::BaseController
  # 账簿是只读视图，门禁在基类 ensure_erp_access（销售端 403），无需再分能力域。

  # 科目余额表：期初 / 本期借贷发生 / 期末，附借贷合计（试算平衡看这两个数相不相等）。
  def balances
    @rows = query_service.balances(from: from_date, to: to_date)
    @rows = @rows.reject { |row| row[:account].is_group? } if params[:leaves_only] == 'true'
    @rows = @rows.select { |row| active_row?(row) } unless params[:include_empty] == 'true'
    @totals = leaf_totals
  end

  # 明细账：某科目（含下级）逐笔分录 + 累计余额，可按维度切片。
  def entries
    account = Current.account.erp_ledger_accounts.find(params[:ledger_account_id])
    @ledger_account = account
    @result = query_service.entries(
      ledger_account: account, from: from_date, to: to_date,
      dimension: params[:dimension], dimension_id: params[:dimension_id]
    )
  end

  # 维度明细账：按客户/供应商/订单/部门/业务员看发生额。
  def dimensions
    account = Current.account.erp_ledger_accounts.find_by(id: params[:ledger_account_id])
    @dimension = params[:dimension].presence || 'customer'
    @rows = query_service.dimension_summary(
      dimension: @dimension, from: from_date, to: to_date, ledger_account: account
    )
  end

  private

  def query_service
    @query_service ||= Erp::LedgerQueryService.new(Current.account)
  end

  def from_date
    params[:from].presence&.to_date || Time.zone.today.beginning_of_month
  end

  def to_date
    params[:to].presence&.to_date || Time.zone.today.end_of_month
  end

  # 没有发生额也没有余额的科目默认不列——109 个科目全列出来财务没法看。
  def active_row?(row)
    row[:opening_micros] != 0 || row[:debit_micros] != 0 || row[:credit_micros] != 0 || row[:closing_micros] != 0
  end

  # 试算平衡取末级科目合计（分类科目是汇总数，再加一遍会翻倍）。
  def leaf_totals
    leaves = @rows.reject { |row| row[:account].is_group? }
    {
      debit_micros: leaves.sum { |row| row[:debit_micros] },
      credit_micros: leaves.sum { |row| row[:credit_micros] }
    }
  end
end
