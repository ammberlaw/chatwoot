class CreateMesOrderForwards < ActiveRecord::Migration[7.1]
  # 业务把生产订单「知会/转发」给某阶段负责人的留痕（谁在何时把订单知会给谁 + 附言）。
  # 与站内通知分开存：通知按收件人各一条且会被读掉，这里是订单维度的审计流水，供订单详情回看。
  def change
    create_table :mes_order_forwards do |t|
      t.bigint :account_id, null: false
      t.bigint :production_order_id, null: false
      t.bigint :sender_id, null: false
      t.string :board_key, null: false
      t.string :stage_label
      t.string :recipient_names
      t.text :note
      t.timestamps
    end

    add_index :mes_order_forwards, [:account_id, :production_order_id]
    add_foreign_key :mes_order_forwards, :mes_production_orders, column: :production_order_id, on_delete: :cascade
  end
end
