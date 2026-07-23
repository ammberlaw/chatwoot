class AddStockShipmentApprovalToMesShipments < ActiveRecord::Migration[7.1]
  def change
    # kind：PRODUCTION=自产出库（生产订单流转，原样）；STOCK=现货直发（业务员开单→主管审核→仓库出库）。
    add_column :mes_shipments, :kind, :string, null: false, default: 'PRODUCTION'
    add_reference :mes_shipments, :manager, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :mes_shipments, :submitted_at, :datetime
    add_column :mes_shipments, :approved_at, :datetime
    add_column :mes_shipments, :reject_reason, :text
  end
end
