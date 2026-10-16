# 生产订单上的物料反馈。
#
# 用户原话：「加一个反馈面板，比如这款机器什么物料延误了交期，采购在这里更新给业务看。」
# 已有的 BOM 行卡点（blocker_kind）管的是「这颗料为什么还没下采购单」——下单之前的事；
# 这里管的是下单之后供应商那边的情况（延误/改期/缺货/到货），责任人在采购，
# 业务只需要看得到并能照着跟客户解释。两件事阶段不同，不混在一张表里。
class CreateMesOrderFeedbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_order_feedbacks do |t|
      t.references :account, null: false, index: false
      t.references :production_order, null: false, index: false
      t.bigint :user_id
      t.string :kind, null: false, default: 'DELAY'
      t.string :material_name
      t.date :promised_date
      t.text :body, null: false
      t.timestamps
    end
    # 面板按订单倒序取，这一条索引就够（单张订单上的反馈是个位数）。
    add_index :mes_order_feedbacks, [:production_order_id, :created_at],
              name: 'index_mes_order_feedbacks_on_order_and_time'
    add_index :mes_order_feedbacks, :account_id
  end
end
