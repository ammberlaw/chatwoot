# 打印次数：销售出库单 / 原料入库单每月要整叠打出来给财务核对，仓库需要一眼分出
# 「打过的」和「还没打的」（2026-10-21）。打一次加一次，不区分打印人。
class AddPrintCountToMesDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_shipments, :print_count, :integer, default: 0, null: false
    add_column :mes_stock_entries, :print_count, :integer, default: 0, null: false

    # 出库单作废留痕。CANCELLED 这个状态从 S0 起就在 STATUSES 里，却从来没有谁能把单
    # 置过去——做错一张待出库的单，删不掉（只许删草稿）、驳不回（驳回只认待审核）、
    # 重开又被「该订单已生成出库单」拦着，整条路是死的（2026-10-21 用户撞上）。
    add_column :mes_shipments, :void_reason, :string
    add_column :mes_shipments, :voided_at, :datetime
    add_column :mes_shipments, :voided_by_id, :bigint
  end
end
