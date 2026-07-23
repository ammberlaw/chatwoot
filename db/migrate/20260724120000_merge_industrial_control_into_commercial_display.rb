# 商显（COMMERCIAL_DISPLAY）与工控（INDUSTRIAL_CONTROL）合并为「商显工控」，沿用 COMMERCIAL_DISPLAY。
# 把 CRM + MES 全部存量 INDUSTRIAL_CONTROL 值重映射过去（含生产订单 spec.template JSON）。
class MergeIndustrialControlIntoCommercialDisplay < ActiveRecord::Migration[7.1]
  OLD = 'INDUSTRIAL_CONTROL'.freeze
  NEW = 'COMMERCIAL_DISPLAY'.freeze

  # 表名 => 列名
  COLUMNS = {
    'crm_products' => 'product_line',
    'crm_customers' => 'product_group',
    'contacts' => 'product_category',
    'mes_bom_templates' => 'product_line',
    'mes_boms' => 'product_line',
    'mes_inspections' => 'product_line',
    'mes_materials' => 'product_line',
    'mes_production_orders' => 'product_line',
    'mes_production_records' => 'product_line',
    'mes_purchase_orders' => 'product_line',
    'mes_serial_numbers' => 'product_line',
    'mes_shipments' => 'product_line',
    'mes_stock_balances' => 'product_line',
    'mes_stock_entries' => 'product_line',
    'mes_warehouses' => 'product_line'
  }.freeze

  def up
    COLUMNS.each do |table, column|
      execute("UPDATE #{table} SET #{column} = '#{NEW}' WHERE #{column} = '#{OLD}'")
    end
    # 生产订单定制规格里的模板标记
    execute(
      "UPDATE mes_production_orders SET spec = jsonb_set(spec, '{template}', '\"#{NEW}\"') " \
      "WHERE spec->>'template' = '#{OLD}'"
    )
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
