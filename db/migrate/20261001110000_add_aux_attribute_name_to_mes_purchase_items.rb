class AddAuxAttributeNameToMesPurchaseItems < ActiveRecord::Migration[7.1]
  def change
    # 辅助属性快照：算料时从生产任务单那行带过来，导出给供应商的采购单要印出来
    # （供应商按「料号 + 辅助属性」才知道具体要哪一种）。存快照而不是引用 ——
    # 任务单后来改了属性，已发出去的采购单上印的还得是当时那个。
    add_column :mes_purchase_items, :aux_attribute_name, :string
  end
end
