class MoveSupplierAndArrivalToMesPurchaseItems < ActiveRecord::Migration[7.1]
  def up
    # 供应商 + 实际到料时间下放到明细行：一张采购单（BOM 算料）几十个物料来自不同供应商、到货时间各异。
    add_reference :mes_purchase_items, :mes_supplier, index: true, null: true
    add_foreign_key :mes_purchase_items, :mes_suppliers, column: :mes_supplier_id, on_delete: :nullify
    add_column :mes_purchase_items, :arrival_date, :datetime

    # 单头不再挂供应商/到料时间。
    remove_foreign_key :mes_purchase_orders, :mes_suppliers
    remove_column :mes_purchase_orders, :mes_supplier_id, :bigint
    remove_column :mes_purchase_orders, :arrival_date, :datetime
  end

  def down
    add_column :mes_purchase_orders, :arrival_date, :datetime
    add_column :mes_purchase_orders, :mes_supplier_id, :bigint
    add_index :mes_purchase_orders, :mes_supplier_id
    add_foreign_key :mes_purchase_orders, :mes_suppliers, column: :mes_supplier_id, on_delete: :nullify

    remove_column :mes_purchase_items, :arrival_date, :datetime
    remove_foreign_key :mes_purchase_items, :mes_suppliers
    remove_reference :mes_purchase_items, :mes_supplier
  end
end
