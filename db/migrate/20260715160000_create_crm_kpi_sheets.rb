class CreateCrmKpiSheets < ActiveRecord::Migration[7.1]
  def change
    # 个人考核表：下发方案给某员工后生成。走 5 状态审批链，含 4 方电子签（ActiveStorage）。
    create_table :crm_kpi_sheets do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_kpi_scheme_id, index: true
      t.bigint :owner_id, index: true # 被考核员工(User)
      t.string :scheme_name
      t.datetime :period_month, null: false
      # PENDING 待填报 / SUBMITTED 待打分 / SCORED 待人事确认 / HR_CONFIRMED 待总经理确认 / ARCHIVED 已归档
      t.string :status, default: 'PENDING', null: false
      t.integer :pass_score
      t.integer :item_score_cap_pct
      # 打分汇总与绩效核算（micros=整数微分）
      t.decimal :total_score, precision: 7, scale: 2
      t.bigint :monthly_salary_micros
      t.integer :performance_ratio
      t.bigint :baseline_target_micros
      t.bigint :performance_base_micros
      t.decimal :payout_coefficient, precision: 6, scale: 3
      t.bigint :actual_payout_micros
      # 审批链的操作人与时间戳（签名文件走 ActiveStorage has_one_attached）
      t.datetime :employee_signed_at
      t.bigint :manager_id
      t.datetime :manager_signed_at
      t.bigint :hr_id
      t.datetime :hr_confirmed_at
      t.bigint :gm_id
      t.datetime :gm_confirmed_at
      t.timestamps
    end
    add_index :crm_kpi_sheets, [:account_id, :period_month]
    add_index :crm_kpi_sheets, [:crm_kpi_scheme_id, :owner_id]
    add_foreign_key :crm_kpi_sheets, :crm_kpi_schemes, column: :crm_kpi_scheme_id, on_delete: :nullify
    add_foreign_key :crm_kpi_sheets, :users, column: :owner_id, on_delete: :nullify

    # 考核表行：从方案指标复制而来，加「完成值/得分/建议分」。
    create_table :crm_kpi_sheet_items do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_kpi_sheet_id, null: false, index: true
      t.string :name, null: false
      t.string :dimension
      t.text :standard
      t.integer :weight
      t.string :baseline_value
      t.string :target_value
      t.string :data_source, default: 'MANUAL', null: false
      t.string :actual_value       # 完成值（员工填）
      t.decimal :score, precision: 7, scale: 2      # 得分（主管定）
      t.decimal :suggested_score, precision: 7, scale: 2 # CRM 建议分
      t.integer :sort_order, default: 0
      t.timestamps
    end
    add_foreign_key :crm_kpi_sheet_items, :crm_kpi_sheets, column: :crm_kpi_sheet_id, on_delete: :cascade

    # 绩效审批人设置（单记录/账号）：指定人事、总经理是谁。
    create_table :crm_performance_settings do |t|
      t.references :account, null: false, index: { unique: true }
      t.bigint :hr_owner_id
      t.bigint :gm_owner_id
      t.timestamps
    end
    add_foreign_key :crm_performance_settings, :users, column: :hr_owner_id, on_delete: :nullify
    add_foreign_key :crm_performance_settings, :users, column: :gm_owner_id, on_delete: :nullify
  end
end
