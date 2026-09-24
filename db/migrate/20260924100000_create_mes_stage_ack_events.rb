# 阶段接单/转交流水。
#
# 原来接单状态只在订单上存一份（stage_ack_at / stage_ack_by_id），
# 阶段事件表也只有每阶段一条（唯一索引 order+stage）。一个阶段两个人接力
#（工程先出/改 BOM，再转给 PMC 投单）时，后接的人会把前一个人的记录覆盖掉，
# 账面上只剩一个接单人——工作量和责任都看不出前后。
#
# 这张表按「发生了什么」逐条记：谁在哪个阶段接的单、谁把单转给了谁。
# 订单上那两个字段保留不动（看板/预警/超时判定都依赖它，是「当前状态」），
# 这里只负责留痕与时间线展示，两者各司其职。
class CreateMesStageAckEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_stage_ack_events do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :production_order, null: false, index: { name: 'idx_mes_stage_ack_events_on_order' },
                                      foreign_key: { to_table: :mes_production_orders, on_delete: :cascade }
      t.string :stage, null: false
      # ACK 接单 / HANDOFF 转交给同阶段另一人
      t.string :kind, null: false
      t.references :actor, null: false, foreign_key: { to_table: :users, on_delete: :cascade }, index: false
      # 仅 HANDOFF：接收人
      t.bigint :to_user_id
      t.text :note
      t.datetime :happened_at, null: false
      t.timestamps
    end

    add_index :mes_stage_ack_events, [:account_id, :production_order_id, :happened_at],
              name: 'idx_mes_stage_ack_events_lookup'
    add_foreign_key :mes_stage_ack_events, :users, column: :to_user_id, on_delete: :nullify
  end
end
