class AddHandledByToCrmDocs < ActiveRecord::Migration[7.1]
  # 经办人：单据业绩归客户归属人(owner_id)，另留痕实际操作/建单的人(handled_by_id)。
  # 共享客户里被共享的助理建 PI/销售订单/报价时用得上。
  def change
    add_reference :crm_pis, :handled_by, null: true, index: true,
                                         foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :crm_sales_orders, :handled_by, null: true, index: true,
                                                  foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :crm_quotes, :handled_by, null: true, index: true,
                                            foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
