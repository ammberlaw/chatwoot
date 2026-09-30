class AddReceivablesEnabledToErpSettings < ActiveRecord::Migration[7.1]
  def change
    # 过渡期开关：账还在金蝶时保持 false，ERP 应收正式启用那天置 true。
    add_column :erp_settings, :receivables_enabled, :boolean, default: false, null: false
  end
end
