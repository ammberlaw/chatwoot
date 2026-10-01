class MoveNotesToMesBomItems < ActiveRecord::Migration[7.1]
  def change
    # 采购注意事项 / 生产备注改挂在用料行上：这两件事本来就是针对某个料说的
    # （「这颗电容只能用村田」「这个壳上批装配压到排线」），挂整单上采购和车间
    # 还得自己对是哪一行。整单级的两列今天刚加、没上过生产，直接撤掉。
    add_column :mes_bom_items, :purchase_note, :text
    add_column :mes_bom_items, :production_note, :text
    remove_column :mes_boms, :purchase_note, :text
    remove_column :mes_boms, :production_note, :text
  end
end
