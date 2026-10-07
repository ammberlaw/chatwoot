# 销售订单补两个业务字段（业务反馈：录单时这几项只能记在备注里，查不了也统计不了）。
#
# insurance_order_no 信保订单号：阿里信保的单号，和 PI 号是两回事，收款对账要用。
# receipt_account_id 收款账户：指向 erp_cash_accounts（哪个银行/平台账户收的款）。
#   不建外键约束——资金账户可能被财务停用或重建，订单上的历史记录不该因此被级联改动；
#   取不到就当没填（前端按 nil 渲染）。
#
# 「结算方式」不新开列：订单上本来就有 payment_term（收款方式，存 crm_option_items
# 的 code，转 ERP 时没填会被拦下「收款方式没填」），一直缺的只是表单上的下拉而已。
class AddSettlementFieldsToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_sales_orders, :insurance_order_no, :string
    add_column :crm_sales_orders, :receipt_account_id, :bigint

    add_index :crm_sales_orders, [:account_id, :insurance_order_no],
              where: 'insurance_order_no IS NOT NULL',
              name: 'index_crm_sales_orders_on_account_and_insurance_no'
  end
end
