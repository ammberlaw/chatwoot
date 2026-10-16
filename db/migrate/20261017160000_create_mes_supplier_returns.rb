# 退料返修（退给供应商）。
#
# 用户原话：「我这边退料出去，多久能回来？是不是要设置一个退出去的时间跟物料返修回来时间呢；
# 是不是需要再做个退料返修回来的模块呢？」
#
# 核心就是两个时间 + 中间这段在外面的天数：退出去那天、修好回来那天。
# 本期**只做台账、不动库存**：返修回来要不要重新入库、要不要质检，用户还没定
# （见 10.16 需求「待确认」）。字段按「以后要接入库/质检也不用改表」的形状留好：
# 每行记了产品档案 id、退出数量、已返回数量，接入库时按行补入库单即可。
class CreateMesSupplierReturns < ActiveRecord::Migration[7.1]
  def change
    create_returns
    create_return_items
  end

  def create_returns
    create_table :mes_supplier_returns do |t|
      t.references :account, null: false, index: false
      t.string :return_no, null: false
      t.references :mes_supplier, null: false, index: false
      # 哪张生产订单的料（可空：有些是库存料，不挂单）
      t.bigint :production_order_id
      t.string :product_line
      t.string :status, null: false, default: 'DRAFT'
      t.date :sent_on      # 退出去那天
      t.date :returned_on  # 修好回来那天
      t.bigint :owner_id
      t.text :reason       # 退料原因（不良/错料/返工…）
      t.text :remark
      t.timestamps
    end
    add_index :mes_supplier_returns, [:account_id, :return_no], unique: true
    add_index :mes_supplier_returns, [:account_id, :status]
    add_index :mes_supplier_returns, :production_order_id
  end

  def create_return_items
    create_table :mes_supplier_return_items do |t|
      t.references :account, null: false, index: false
      t.references :supplier_return, null: false, index: false
      t.bigint :crm_product_id
      t.decimal :qty, precision: 14, scale: 3, null: false, default: 0
      t.decimal :returned_qty, precision: 14, scale: 3, null: false, default: 0
      t.string :unit
      t.text :remark
      t.timestamps
    end
    add_index :mes_supplier_return_items, :supplier_return_id
    add_index :mes_supplier_return_items, :crm_product_id
  end
end
