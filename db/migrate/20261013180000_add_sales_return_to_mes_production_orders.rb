class AddSalesReturnToMesProductionOrders < ActiveRecord::Migration[7.1]
  # 退回给业务：工程/PMC 做生产任务单时发现业务没把物料细节确认清楚，做不下去，
  # 把单退回去让业务重新确认，而不是硬着头皮往下走、或者私下找人问。
  # 退回要填原因——业务收到只知道被退了、不知道哪个细节没说清，还得回头问一遍。
  def change
    add_column :mes_production_orders, :sales_return_at, :datetime
    add_column :mes_production_orders, :sales_return_by_id, :bigint
    add_column :mes_production_orders, :sales_return_reason, :text
    add_column :mes_production_orders, :sales_return_resolved_at, :datetime
    add_column :mes_production_orders, :sales_return_resolved_by_id, :bigint

    # 「待业务确认」的单要能一把捞出来（业务员的待办、看板角标）。
    add_index :mes_production_orders, [:account_id, :sales_return_at],
              where: 'sales_return_at IS NOT NULL AND sales_return_resolved_at IS NULL',
              name: 'index_mes_production_orders_awaiting_sales_confirm'
  end
end
