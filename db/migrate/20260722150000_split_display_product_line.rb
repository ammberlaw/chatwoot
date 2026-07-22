class SplitDisplayProductLine < ActiveRecord::Migration[7.1]
  # 产品线由 DISPLAY(商显+工控合一) 拆成 COMMERCIAL_DISPLAY(商显) 与 INDUSTRIAL_CONTROL(工控)。
  LINE_TABLES = %w[
    mes_production_orders mes_boms mes_materials mes_warehouses mes_purchase_orders
    mes_stock_entries mes_stock_balances mes_shipments mes_production_records
    mes_inspections mes_serial_numbers
  ].freeze

  def up
    # 产品档案：名称含「工控」→ 工控线，其余 DISPLAY → 商显线。
    execute("UPDATE crm_products SET product_line = 'INDUSTRIAL_CONTROL' WHERE product_line = 'DISPLAY' AND name LIKE '%工控%'")
    execute("UPDATE crm_products SET product_line = 'COMMERCIAL_DISPLAY' WHERE product_line = 'DISPLAY'")

    # 有关联成品的单据按成品新线回填。
    %w[mes_production_orders mes_boms].each do |t|
      execute("UPDATE #{t} m SET product_line = p.product_line FROM crm_products p WHERE m.crm_product_id = p.id AND m.product_line = 'DISPLAY'")
    end
    # 其余仍为 DISPLAY 的（无成品可推）默认归商显线。
    LINE_TABLES.each do |t|
      execute("UPDATE #{t} SET product_line = 'COMMERCIAL_DISPLAY' WHERE product_line = 'DISPLAY'")
    end
  end

  def down
    execute("UPDATE crm_products SET product_line = 'DISPLAY' WHERE product_line IN ('COMMERCIAL_DISPLAY', 'INDUSTRIAL_CONTROL')")
    LINE_TABLES.each do |t|
      execute("UPDATE #{t} SET product_line = 'DISPLAY' WHERE product_line IN ('COMMERCIAL_DISPLAY', 'INDUSTRIAL_CONTROL')")
    end
  end
end
