# 工程 BOM 按阶段填预估天数（采购/入库/领料/生产/成品入库），系统求和算预计完工。
# 不含销售出库（物流不进 BOM 预估）。
class AddStageLeadDaysToMesBoms < ActiveRecord::Migration[7.1]
  def change
    change_table :mes_boms, bulk: true do |t|
      t.integer :purchasing_days
      t.integer :material_inbound_days
      t.integer :picking_days
      t.integer :production_days
      t.integer :fg_inbound_days
    end
  end
end
