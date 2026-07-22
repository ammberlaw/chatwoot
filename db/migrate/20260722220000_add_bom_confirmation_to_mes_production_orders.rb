class AddBomConfirmationToMesProductionOrders < ActiveRecord::Migration[7.1]
  def change
    change_table :mes_production_orders, bulk: true do |t|
      t.datetime :bom_confirmed_at              # 业务二次确认 BOM 的时间（空=尚未确认）
      t.bigint :bom_confirmed_by_id, index: true # 确认人（业务员）
    end

    add_foreign_key :mes_production_orders, :users, column: :bom_confirmed_by_id, on_delete: :nullify
  end
end
