# 原料存货 FIFO：批次层原来只按成品（crm_product_id）建，可领料行大多挂的是物料档
# （mes_material_id，dev 里 11:2，生产上更悬殊）。要把先进先出铺到原料，层和消耗
# 都得能按物料记。
#
# 两个 id 都可空、但不能都空：同一颗料在不同单据上挂法不一（屏/主板这些建在商品档里），
# 两种都认，由 Erp::StockLayer.for_item 归一。
class AddMaterialToStockLayers < ActiveRecord::Migration[7.1]
  def change
    change_column_null :erp_stock_layers, :crm_product_id, true
    change_column_null :erp_stock_consumptions, :crm_product_id, true

    add_column :erp_stock_layers, :mes_material_id, :bigint
    add_column :erp_stock_consumptions, :mes_material_id, :bigint

    # FIFO 取层是热路径（每张领料单每行一次），按「料 + 仓 + 有余量」走索引。
    add_index :erp_stock_layers, [:account_id, :mes_material_id, :warehouse_id],
              name: 'index_erp_stock_layers_on_material_and_wh'
    add_index :erp_stock_consumptions, :mes_material_id

    # 成品层必有成品、原料层必有物料或成品，二者不能都空——都空的层取不出来也扣不掉。
    add_check_constraint :erp_stock_layers,
                         'crm_product_id IS NOT NULL OR mes_material_id IS NOT NULL',
                         name: 'erp_stock_layers_item_present'
  end
end
