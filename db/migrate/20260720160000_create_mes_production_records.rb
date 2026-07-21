class CreateMesProductionRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_production_records do |t|
      t.references :account, null: false, index: true
      t.bigint :production_order_id, null: false, index: true
      t.string :operation_name
      t.decimal :qty_completed, precision: 14, scale: 3, default: 0, null: false
      t.decimal :qty_returned, precision: 14, scale: 3, default: 0, null: false
      t.decimal :qty_scrap, precision: 14, scale: 3, default: 0, null: false
      t.bigint :operator_id, index: true
      t.datetime :recorded_at
      t.text :remark
      t.timestamps
    end

    add_foreign_key :mes_production_records, :mes_production_orders, column: :production_order_id, on_delete: :cascade
    add_foreign_key :mes_production_records, :users, column: :operator_id, on_delete: :nullify
  end
end
