class AddCashFlowItemToErpVoucherLines < ActiveRecord::Migration[7.1]
  def change
    # 现金流量项目：只对货币资金科目的分录行有意义，留空则报表按对方科目自动推断。
    # 存国标项目编码字符串而不是外键——项目表由准则固定，不给用户增删（见 Erp::CashFlowItem）。
    add_column :erp_voucher_lines, :cash_flow_item, :string
    add_index :erp_voucher_lines, %i[account_id cash_flow_item]
  end
end
