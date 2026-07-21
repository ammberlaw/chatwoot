class AddStageAckToMesProductionOrders < ActiveRecord::Migration[7.1]
  # P1 接单确认：接单状态挂在订单「当前阶段」上，进阶段即清零、计时以 entered_at 为准。
  def change
    add_column :mes_production_orders, :stage_ack_at, :datetime
    add_column :mes_production_orders, :stage_ack_by_id, :bigint
    add_index :mes_production_orders, :stage_ack_by_id

    # 下游「拒收打回」时把原因记在退回到的阶段事件上。
    add_column :mes_production_order_stage_events, :note, :text
  end
end
