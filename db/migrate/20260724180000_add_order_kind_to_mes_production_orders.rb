class AddOrderKindToMesProductionOrders < ActiveRecord::Migration[7.1]
  def change
    # CUSTOMER=按单生产（归属业务员收敛）；STOCK=外贸备货生产（全业务可见，owner 复用为责任人）。
    add_column :mes_production_orders, :order_kind, :string, null: false, default: 'CUSTOMER'
    add_index :mes_production_orders, [:account_id, :order_kind]
  end
end
