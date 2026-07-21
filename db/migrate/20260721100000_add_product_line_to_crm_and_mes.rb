# 产品线维度（商显工控 / 平板电脑）：页面按产线分流。
# 来源真值挂 crm_products，各 MES 单据 create 时由父级/主数据 stamp（Mes::LineScoped）。
class AddProductLineToCrmAndMes < ActiveRecord::Migration[7.1]
  TABLES = %i[
    crm_products
    mes_production_orders
    mes_boms
    mes_materials
    mes_warehouses
    mes_purchase_orders
    mes_stock_entries
    mes_stock_balances
    mes_shipments
    mes_production_records
    mes_inspections
    mes_serial_numbers
  ].freeze

  def change
    TABLES.each do |table|
      add_column table, :product_line, :string
      add_index table, [:account_id, :product_line], name: "index_#{table}_on_account_and_product_line"
    end
  end
end
