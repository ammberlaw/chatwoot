# 销项税率落到单据上（财务 2026-10-06 拍板：收入在销售出库时点确认，凭证含销项税行）。
# 人民币单默认取账套设置里的默认税率、美金等外币单默认 0，业务员可逐单改；
# 税率为 0 的单出库凭证不出销项税那一行。
class AddTaxRateToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_sales_orders, :tax_rate, :integer unless column_exists?(:crm_sales_orders, :tax_rate)
    add_column :erp_settings, :default_output_tax_rate, :integer, default: 13, null: false unless column_exists?(:erp_settings, :default_output_tax_rate)

    # 存量回填：人民币 13、其余币种 0。欧元单一并按外币落 0，
    # 财务会把那几张自己折成美金后再核对（用户 2026-10-06 定）。
    execute <<~SQL.squish
      UPDATE crm_sales_orders
         SET tax_rate = CASE WHEN order_currency = 'CNY' THEN 13 ELSE 0 END
       WHERE tax_rate IS NULL
    SQL
  end

  def down
    remove_column :crm_sales_orders, :tax_rate, if_exists: true
    remove_column :erp_settings, :default_output_tax_rate, if_exists: true
  end
end
