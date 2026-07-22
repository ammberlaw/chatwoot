class AddSpecToMesProductionOrders < ActiveRecord::Migration[7.1]
  # 定制生产订单：按产品线（平板/显示器）填的规格与定制要求，字段多且会变，用 jsonb 灵活存。
  def change
    add_column :mes_production_orders, :spec, :jsonb, null: false, default: {}
  end
end
