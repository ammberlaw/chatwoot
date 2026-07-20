class CreateMesProductionOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_production_orders do |t|
      t.references :account, null: false, index: true
      t.string :order_no, null: false
      t.bigint :crm_sales_order_id, index: true
      t.bigint :crm_product_id, index: true
      t.string :product_name, null: false
      t.decimal :qty, precision: 14, scale: 3, null: false
      t.string :unit
      t.decimal :produced_qty, precision: 14, scale: 3, default: 0, null: false
      # bom_id 外键在 S1 建 mes_boms 时补加
      t.bigint :bom_id, index: true
      t.string :stage, default: 'SALES_CONFIRMED', null: false
      t.string :status, default: 'IN_PROGRESS', null: false
      t.datetime :delivery_date
      t.datetime :planned_start_date
      t.datetime :planned_end_date
      t.datetime :actual_start_date
      t.datetime :actual_end_date
      t.bigint :owner_id, index: true
      t.text :remark
      t.timestamps
    end

    add_index :mes_production_orders, [:account_id, :order_no], unique: true
    add_index :mes_production_orders, [:account_id, :stage]
    add_foreign_key :mes_production_orders, :crm_sales_orders, column: :crm_sales_order_id, on_delete: :nullify
    add_foreign_key :mes_production_orders, :crm_products, column: :crm_product_id, on_delete: :nullify
    add_foreign_key :mes_production_orders, :users, column: :owner_id, on_delete: :nullify
  end
end
