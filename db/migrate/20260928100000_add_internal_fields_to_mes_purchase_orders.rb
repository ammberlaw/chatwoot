# 采购单三件：对内备注（不进发给供应商的模板）、预览/导出次数（防漏传）、
# 额外关联的生产订单（同款物料多单共用时一张采购单带多张生产订单）。
class AddInternalFieldsToMesPurchaseOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_purchase_orders, :internal_remark, :text
    add_column :mes_purchase_orders, :export_count, :integer, default: 0, null: false
    add_column :mes_purchase_orders, :last_exported_at, :datetime
    add_column :mes_purchase_orders, :extra_production_order_ids, :bigint, array: true, default: [], null: false
    add_index :mes_purchase_orders, :extra_production_order_ids, using: :gin,
              name: 'index_mes_purchase_orders_on_extra_production_order_ids'
  end
end
