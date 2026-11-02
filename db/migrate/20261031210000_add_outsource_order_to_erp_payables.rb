# 委外加工费挂应付：一张委外加工单对应一条应付，按已入库数量累计。
# 没有这一列的话每次产品入库都会新建一条应付，同一张加工单挂出好几笔账。
class AddOutsourceOrderToErpPayables < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_payables, :mes_outsource_order_id, :bigint
    add_index :erp_payables, [:account_id, :mes_outsource_order_id],
              name: 'index_erp_payables_on_account_and_outsource_order'
  end
end
