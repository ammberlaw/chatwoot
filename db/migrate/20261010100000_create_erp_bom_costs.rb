class CreateErpBomCosts < ActiveRecord::Migration[7.1]
  def change
    # BOM 成本表：每个商品编码一条标准加工成本。
    # ⚠️ 按**产品档案**（商品编码）挂，不是按 Mes::Bom——名字随用户叫法。
    # 产品名称/规格型号不在这里存一份，渲染时从产品档案带，避免改了档案这边还是旧的。
    create_table :erp_bom_costs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :crm_product, null: false, foreign_key: { to_table: :crm_products, on_delete: :cascade }
      t.bigint :process_fee_micros, null: false, default: 0   # 加工费（生产人工）单价
      t.bigint :overhead_fee_micros, null: false, default: 0  # 制造费用单价
      t.text :remark
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :erp_bom_costs, [:account_id, :crm_product_id], unique: true, name: 'idx_erp_bom_costs_on_account_product'

    # 一张生产订单现在会归集出多条成本行（材料 / 人工 / 制造费用），
    # 原唯一索引只认 (source_type, source_id)，第二条就撞键了。把口径并进去。
    remove_index :erp_order_costs, name: 'index_erp_order_costs_on_source'
    add_index :erp_order_costs, [:account_id, :source_type, :source_id, :cost_type],
              unique: true, where: 'source_type IS NOT NULL', name: 'index_erp_order_costs_on_source'
  end
end
