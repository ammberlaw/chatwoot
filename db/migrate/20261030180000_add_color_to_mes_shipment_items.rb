# 外贸现货单转出库时，业务在每行成品上标颜色。
#
# 为什么不塞进 remark：备注是写给仓管的自由交代（「先发这批」「客户要加护角」），
# 颜色混进去以后想按颜色统计、导出拣货单都得靠猜文本。
#
# 为什么不做成枚举：生产上 mes_boms.bare_color 的真实值是「黑色1000」
# 「蓝色600、粉色600、红色600、绿色200」这种颜色带数量的写法，枚举装不下。
# 这里存字符串，前端给常用颜色的下拉当快捷入口，特殊情况仍可留空去备注里写。
class AddColorToMesShipmentItems < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_shipment_items, :color, :string
  end
end
