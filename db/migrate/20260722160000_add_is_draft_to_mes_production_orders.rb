class AddIsDraftToMesProductionOrders < ActiveRecord::Migration[7.1]
  # 生产订单存草稿：草稿仅创建人（owner）可见，不进看板/预警/待接单。
  def change
    add_column :mes_production_orders, :is_draft, :boolean, null: false, default: false
    add_index :mes_production_orders, [:account_id, :is_draft]
  end
end
