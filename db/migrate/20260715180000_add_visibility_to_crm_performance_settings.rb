class AddVisibilityToCrmPerformanceSettings < ActiveRecord::Migration[7.1]
  def change
    # 绩效板块按角色可见性开关（默认全开=保持现状）。管理员始终可见。
    add_column :crm_performance_settings, :scheme_visible_sales, :boolean, default: true, null: false
    add_column :crm_performance_settings, :scheme_visible_manager, :boolean, default: true, null: false
    add_column :crm_performance_settings, :sheet_visible_sales, :boolean, default: true, null: false
    add_column :crm_performance_settings, :sheet_visible_manager, :boolean, default: true, null: false
  end
end
