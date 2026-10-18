# 一张入库单收多张采购单的货：同一家供应商同一天送来好几张单的料，
# 仓管要能一次收完，而不是开三张入库单（10.17 反馈 A2「有一张单多个采购单的要一起入」）。
# 形态照采购单关联多张生产订单那套（mes_purchase_orders.extra_production_order_ids）。
class AddExtraPurchaseOrdersToMesStockEntries < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_stock_entries, :extra_purchase_order_ids, :bigint, array: true, default: [], null: false
    add_index :mes_stock_entries, :extra_purchase_order_ids, using: :gin
  end
end
