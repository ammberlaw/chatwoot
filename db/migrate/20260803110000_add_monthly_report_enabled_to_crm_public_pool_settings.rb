class AddMonthlyReportEnabledToCrmPublicPoolSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_public_pool_settings, :monthly_report_enabled, :boolean, default: true, null: false
  end
end
