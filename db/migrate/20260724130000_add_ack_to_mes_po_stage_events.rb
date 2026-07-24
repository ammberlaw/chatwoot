# 阶段事件上持久化「接单」留痕：订单推进后 mes_production_orders.stage_ack_at 会清零，
# 历史无从统计。把每次接单时刻/接单人落到对应阶段事件上，供生产看板「各环节接单响应时长」统计。
class AddAckToMesPoStageEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_production_order_stage_events, :acked_at, :datetime
    add_reference :mes_production_order_stage_events, :acked_by,
                  foreign_key: { to_table: :users, on_delete: :nullify }, null: true
  end
end
