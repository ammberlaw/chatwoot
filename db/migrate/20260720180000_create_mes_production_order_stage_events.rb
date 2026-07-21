class CreateMesProductionOrderStageEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_production_order_stage_events do |t|
      t.references :account, null: false, index: true
      t.bigint :production_order_id, null: false, index: true
      t.string :stage, null: false
      t.datetime :entered_at, null: false
      t.bigint :actor_id
      t.timestamps
    end

    add_index :mes_production_order_stage_events, [:production_order_id, :stage],
              unique: true, name: 'index_mes_po_stage_events_unique'
    add_foreign_key :mes_production_order_stage_events, :mes_production_orders,
                    column: :production_order_id, on_delete: :cascade
    add_foreign_key :mes_production_order_stage_events, :users, column: :actor_id, on_delete: :nullify
  end
end
