# BOM 用料行加「卡点」：这颗料为什么还没下采购单。
#
# 用户原话：「其中一项电子物料工程没有确认，或者一项包装物料业务没有确认，或者业务文件
# 还没发，还有样品在打样中……这些物料都是没有下达采购订单到供应商的，这也不能是我这边
# 没做生产单，也不能是采购不下单的原因……那这个要怎么体现在系统里面呢？其余相关的人
# 怎么看到这个单问题点是卡在哪里呢？」
#
# 原来系统只认两种状态：下了单 / 没下单。没下单的一律看着像采购在拖，
# 实际上一大半是在等客户确认、等业务发文件、等打样——责任人根本不在采购。
class AddBlockerToMesBomItems < ActiveRecord::Migration[7.0]
  def change
    # WAITING_CUSTOMER 等客户确认 / WAITING_FILE 等业务文件 / WAITING_ENGINEERING 等工程确认
    # / SAMPLING 打样中 / OTHER 其它；空 = 没卡住
    add_column :mes_bom_items, :blocker_kind, :string
    add_column :mes_bom_items, :blocker_note, :text
    # 这个卡点等谁解决（通常是业务或工程，不是采购）
    add_column :mes_bom_items, :blocker_owner_id, :bigint
    add_column :mes_bom_items, :blocked_at, :datetime
    add_column :mes_bom_items, :blocker_cleared_at, :datetime
    add_index :mes_bom_items, [:bom_id, :blocker_kind], name: 'index_mes_bom_items_on_bom_and_blocker'
  end
end
