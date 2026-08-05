class AddReturnRemarkAndSubmitDeadlineToKpi < ActiveRecord::Migration[7.1]
  def change
    change_table :crm_kpi_sheets, bulk: true do |t|
      t.text :remark              # 备注/补充条款（主管/管理员填，随表存档，全员可见）
      t.text :return_reason       # 最近一次退回原因（展示给员工）
      t.datetime :returned_at     # 最近一次退回时间
      t.bigint :returned_by_id    # 退回人
    end
    add_index :crm_kpi_sheets, :returned_by_id
    add_foreign_key :crm_kpi_sheets, :users, column: :returned_by_id, on_delete: :nullify

    # 业务员提交截止日：考核月「次月」的第 N 天（1-28）前须提交，逾期禁提交；留空=不限制。
    add_column :crm_performance_settings, :submit_deadline_day, :integer
  end
end
