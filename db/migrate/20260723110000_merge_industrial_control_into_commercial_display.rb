class MergeIndustrialControlIntoCommercialDisplay < ActiveRecord::Migration[7.1]
  # 产品分组由三合二：商显(COMMERCIAL_DISPLAY)+工控(INDUSTRIAL_CONTROL) 合并为「商显工控」，
  # 沿用 COMMERCIAL_DISPLAY 码。把现有「工控」客户/联系人并入 COMMERCIAL_DISPLAY。
  def up
    execute("UPDATE crm_customers SET product_group = 'COMMERCIAL_DISPLAY' WHERE product_group = 'INDUSTRIAL_CONTROL'")
    execute("UPDATE contacts SET product_category = 'COMMERCIAL_DISPLAY' WHERE product_category = 'INDUSTRIAL_CONTROL'")
  end

  def down
    raise ActiveRecord::IrreversibleMigration, '合并后无法区分原「工控」与「商显」'
  end
end
