class CreateErpStockLayers < ActiveRecord::Migration[7.1]
  # 成品 FIFO 存货核算（与金蝶同口径）。金额只活在 erp_* 表（ERP_SPEC §13-1），
  # 所以批次层建在 ERP 侧，MES 过账时回调——与 CostRollupService/OrderCompletionService 同模式。
  #
  # 只做成品：库存单卖的是成品；原材料耗用已由 CostRollupService 按领料归到定制订单，
  # 再做一遍存货核算就是重复计算。
  def change
    create_layers
    create_consumptions
  end

  private

  def create_layers
    create_table :erp_stock_layers do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_product_id, null: false
      t.bigint :warehouse_id, null: false
      t.decimal :qty_in, precision: 16, scale: 3, null: false
      t.decimal :qty_remaining, precision: 16, scale: 3, null: false
      # 单位成本（本位币）。外购=采购行金额÷数量；自产=生产订单归集成本÷完工数量；期初=财务录。
      t.bigint :unit_cost_micros, null: false, default: 0
      t.datetime :received_at, null: false # FIFO 排序键
      t.string :source_type, null: false   # Mes::StockEntry / Erp::OpeningInventory
      t.bigint :source_id
      t.text :remark
      t.timestamps
    end
    # FIFO 取层：按 (账户,产品,仓库) 过滤、received_at 升序，只看还有余量的层。
    add_index :erp_stock_layers, [:account_id, :crm_product_id, :warehouse_id, :received_at],
              name: 'idx_erp_stock_layers_fifo'
    add_index :erp_stock_layers, [:source_type, :source_id]
    add_foreign_key :erp_stock_layers, :crm_products, column: :crm_product_id, on_delete: :restrict
    add_foreign_key :erp_stock_layers, :mes_warehouses, column: :warehouse_id, on_delete: :restrict
  end

  # 出库耗用了哪些层、各扣多少——作废出库单要按这个原样还回去，不能凭 FIFO 再算一遍
  # （中间又进过货的话，重算出来的层跟当初消耗的根本不是同一批）。
  def create_consumptions
    create_table :erp_stock_consumptions do |t|
      t.references :account, null: false, index: true
      t.bigint :stock_layer_id, null: false
      t.bigint :mes_stock_entry_id, null: false # 出库单
      t.bigint :crm_product_id, null: false
      t.decimal :qty, precision: 16, scale: 3, null: false
      # 本位币。存货成本天然是本位币（MES 采购/成本价都是人民币口径），
      # 列名写明 base_ 让「跨币种求和」守卫一眼看出不是原币。
      t.bigint :base_amount_micros, null: false # qty × 该层单价
      t.timestamps
    end
    add_index :erp_stock_consumptions, [:account_id, :mes_stock_entry_id],
              name: 'idx_erp_stock_consumptions_entry'
    add_index :erp_stock_consumptions, :stock_layer_id
    add_foreign_key :erp_stock_consumptions, :erp_stock_layers, column: :stock_layer_id, on_delete: :restrict
    add_foreign_key :erp_stock_consumptions, :mes_stock_entries, column: :mes_stock_entry_id, on_delete: :cascade
  end
end
