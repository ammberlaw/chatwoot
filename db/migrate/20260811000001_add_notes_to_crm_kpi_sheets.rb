class AddNotesToCrmKpiSheets < ActiveRecord::Migration[7.1]
  # 下发考核表时，把方案的「评分与绩效发放规则/考核结果应用」两段说明快照到表上，
  # 使考核表成为独立记录（方案后续被改/删不影响已下发的表）。
  def change
    add_column :crm_kpi_sheets, :payout_note, :text
    add_column :crm_kpi_sheets, :result_note, :text
  end
end
