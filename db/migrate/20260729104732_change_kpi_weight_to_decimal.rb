# 考核指标权重支持小数（如林辉方案两店 CPF 各 7.5 分）。方案指标 + 考核表快照两张表同改。
class ChangeKpiWeightToDecimal < ActiveRecord::Migration[7.1]
  def up
    change_column :crm_scheme_items, :weight, :decimal, precision: 5, scale: 1
    change_column :crm_kpi_sheet_items, :weight, :decimal, precision: 5, scale: 1
  end

  def down
    change_column :crm_scheme_items, :weight, :integer
    change_column :crm_kpi_sheet_items, :weight, :integer
  end
end
