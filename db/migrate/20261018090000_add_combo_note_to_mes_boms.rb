# 生产任务单的「搭配说明」：个别单要单独写清楚机器和皮套怎么配
# （「蓝皮套500+蓝机500、粉皮套500+金机500…」），和整单备注不是一回事——
# 那栏写的是工艺/包装要求，搭配关系混进去车间会看漏。
class AddComboNoteToMesBoms < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_boms, :combo_note, :text
  end
end
