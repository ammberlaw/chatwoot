class AddResultNoteToCrmKpiSchemes < ActiveRecord::Migration[7.1]
  def change
    # 考核结果应用（试用期/激励档/异议等政策说明），与 payout_note（发放规则）并列。
    add_column :crm_kpi_schemes, :result_note, :text
  end
end
