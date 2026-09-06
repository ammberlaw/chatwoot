class AddSourceIndexToErpOrderCosts < ActiveRecord::Migration[7.1]
  # 自动归集的成本行按来源单据唯一（一张生产订单一条），防并发/重复归集写出两条。
  # 手工录入的行 source_type 为空，不受此约束——partial index 只管有来源的。
  def change
    add_index :erp_order_costs, [:account_id, :source_type, :source_id],
              unique: true,
              where: 'source_type IS NOT NULL',
              name: 'index_erp_order_costs_on_source'
  end
end
