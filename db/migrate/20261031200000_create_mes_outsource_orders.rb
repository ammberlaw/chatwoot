# 委外加工单：自己的料发给加工厂，加工厂做好还回来，我们付加工费。
#
# 与「外购」(mes_production_orders.is_outsourced) 不是一回事：外购是整台成品买进来、
# 料和过程都不是我们的；委外是**料还是我们的**，只是换了个地方加工，所以料要跟着单据走，
# 在委外仓记一笔，不能凭空消失。
#
# 生产上四个委外仓（品汇芯/好星/星佑鑫/优橙）压着真实的料，但 2026-10-07 期初之后
# 一张进出单都没有——因为根本没有单据可开。这组表就是补这一段。
class CreateMesOutsourceOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_outsource_orders do |t|
      t.bigint :account_id, null: false
      t.string :order_no, null: false
      # 从生产订单转委外（用户 2026-10-31 定）：销售订单→生产订单→委外加工→入库→发货 连成一条链。
      t.bigint :production_order_id
      t.bigint :mes_supplier_id, null: false # 加工厂
      t.string :product_line                 # 事业部
      t.string :status, null: false, default: 'DRAFT'
      t.date :doc_date, null: false
      t.date :delivery_date                  # 交期
      # 产出：一张加工单做一个成品（从生产订单带过来）
      t.bigint :crm_product_id, null: false
      t.decimal :qty, precision: 16, scale: 3, null: false, default: 0
      t.string :unit
      t.bigint :mes_warehouse_id             # 委外仓：料发到这里，产出也从这里收
      t.bigint :to_warehouse_id              # 产出入哪个仓（成品仓）
      # 加工费：按件计价（金蝶单上 48.00 未税 / 52.80 含税 / 税率 10）。
      # 与采购单同一套写法：存一个单价 + 一个「这个价含不含税」的标志。
      t.bigint :fee_rate_micros, null: false, default: 0
      t.boolean :fee_tax_included, null: false, default: false
      t.decimal :tax_rate, precision: 6, scale: 2, null: false, default: 0
      t.bigint :owner_id
      t.text :remark
      t.timestamps
    end
    add_index :mes_outsource_orders, [:account_id, :order_no], unique: true
    add_index :mes_outsource_orders, [:account_id, :status]
    add_index :mes_outsource_orders, [:account_id, :product_line]
    add_index :mes_outsource_orders, :production_order_id
    add_index :mes_outsource_orders, :mes_supplier_id

    # 用料明细：从生产任务单的 BOM 带过来，可改。
    # 分子/分母/损耗率照搬金蝶口径：标准用量 = 产出数量 × 分子/分母 × (1 + 损耗率)
    create_table :mes_outsource_materials do |t|
      t.bigint :account_id, null: false
      t.bigint :outsource_order_id, null: false
      t.bigint :mes_material_id
      t.bigint :crm_product_id
      t.string :unit
      t.decimal :qty_numerator, precision: 16, scale: 6, null: false, default: 1
      t.decimal :qty_denominator, precision: 16, scale: 6, null: false, default: 1
      t.decimal :loss_rate, precision: 6, scale: 2, null: false, default: 0
      t.decimal :std_qty, precision: 16, scale: 3, null: false, default: 0
      t.bigint :from_warehouse_id # 从哪个仓发
      t.text :remark
      t.timestamps
    end
    add_index :mes_outsource_materials, :outsource_order_id
    add_index :mes_outsource_materials, :account_id

    # 发料 / 入库 / 退料三张单都复用 mes_stock_entries（一表多用），靠这一列挂回加工单。
    add_column :mes_stock_entries, :outsource_order_id, :bigint
    add_index :mes_stock_entries, :outsource_order_id
  end
end
