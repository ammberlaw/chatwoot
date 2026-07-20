class AddBomFkToMesProductionOrders < ActiveRecord::Migration[7.1]
  def change
    add_foreign_key :mes_production_orders, :mes_boms, column: :bom_id, on_delete: :nullify
  end
end
