class CreateMesNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_notifications do |t|
      t.references :account, null: false, index: true
      t.bigint :recipient_id, null: false          # 收件人（user）
      t.bigint :production_order_id                 # 关联生产订单（可空）
      t.string :kind, null: false                   # 通知类型（approval_pending / stage_assigned …）
      t.string :title, null: false
      t.text :body
      t.datetime :read_at                           # 空=未读
      t.timestamps
    end

    add_index :mes_notifications, [:account_id, :recipient_id, :read_at]
    add_index :mes_notifications, :production_order_id
    add_foreign_key :mes_notifications, :users, column: :recipient_id, on_delete: :cascade
    add_foreign_key :mes_notifications, :mes_production_orders, column: :production_order_id, on_delete: :cascade
  end
end
