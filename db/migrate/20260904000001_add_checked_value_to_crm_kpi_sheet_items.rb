class AddCheckedValueToCrmKpiSheetItems < ActiveRecord::Migration[7.1]
  # 核对完成值：员工填的 actual_value 原样留痕，主管核对后填此列；得分以核对值优先。
  def change
    add_column :crm_kpi_sheet_items, :checked_value, :string
  end
end
