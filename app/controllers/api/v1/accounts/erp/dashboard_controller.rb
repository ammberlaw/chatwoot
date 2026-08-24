# 财务看板（E0 占位）：返回零值 KPI + 当前成员的 ERP 能力域。
# 真实数据在各切片落地后接入（回款/应收/应付=E3，资金/毛利=E4）。
class Api::V1::Accounts::Erp::DashboardController < Api::V1::Accounts::Erp::BaseController
  def show
    render json: {
      kpis: {
        month_receipt: 0,       # 本月回款（E3）
        receivable_balance: 0,  # 应收余额（E3）
        overdue_receivable: 0,  # 逾期应收（E3）
        payable_balance: 0,     # 应付余额（E3）
        cash_balance: 0,        # 资金余额（E4）
        month_profit: 0         # 本月毛利（E4）
      },
      capabilities: Current.account_user&.erp_capability_list || []
    }
  end
end
