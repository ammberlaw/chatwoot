class AddMaterialCostToErpBomCosts < ActiveRecord::Migration[7.1]
  def change
    # 材料与包装成本。原先这张表只有加工费/制费，材料成本要点开看 BOM 明细才有，
    # 而多数成品根本没做 BOM（74 个机型里 0 个有），等于看不到材料钱。
    add_column :erp_bom_costs, :material_cost_micros, :bigint, default: 0, null: false
    add_column :erp_bom_costs, :packaging_cost_micros, :bigint, default: 0, null: false

    # 这行成本是人工维护的还是采购单同步来的。将来接「采购单自动同步」时，
    # 不看来源就会把人工维护的值无声覆盖掉（反过来也一样）。
    add_column :erp_bom_costs, :cost_source, :string
    # 成本基准日：报价参考时要知道这是哪天的价，不然半年前的料价拿去报今天的单。
    add_column :erp_bom_costs, :cost_as_of, :date
  end
end
