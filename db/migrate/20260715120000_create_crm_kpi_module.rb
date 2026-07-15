class CreateCrmKpiModule < ActiveRecord::Migration[7.1]
  def change
    # 考核方案（月度可编辑）。对应 Twenty A-CRM kpiScheme。
    create_table :crm_kpi_schemes do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.datetime :scheme_month, null: false
      t.integer :pass_score, default: 70
      t.integer :item_score_cap_pct, default: 120
      t.text :payout_note
      t.string :status, default: 'DRAFT', null: false
      t.timestamps
    end
    add_index :crm_kpi_schemes, [:account_id, :scheme_month]

    # 考核指标（方案子项，随方案级联删除）。对应 schemeItem。
    create_table :crm_scheme_items do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_kpi_scheme_id, null: false, index: true
      t.string :name, null: false
      t.string :dimension
      t.text :standard
      t.integer :weight
      t.string :baseline_value
      t.string :target_value
      t.string :data_source, default: 'MANUAL', null: false
      t.integer :sort_order, default: 0
      t.timestamps
    end
    add_foreign_key :crm_scheme_items, :crm_kpi_schemes, column: :crm_kpi_scheme_id, on_delete: :cascade

    # 发放系数档（方案子项，随方案级联删除）。对应 payoutTier。
    create_table :crm_payout_tiers do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_kpi_scheme_id, null: false, index: true
      t.string :name, null: false
      t.integer :min_score
      t.integer :max_score
      t.decimal :coefficient, precision: 6, scale: 3
      t.boolean :proportional, default: false
      t.integer :sort_order, default: 0
      t.timestamps
    end
    add_foreign_key :crm_payout_tiers, :crm_kpi_schemes, column: :crm_kpi_scheme_id, on_delete: :cascade

    # 员工薪资配置（仅管理员可见，薪资敏感）。对应 employeeComp。owner=业务员(User)。
    create_table :crm_employee_comps do |t|
      t.references :account, null: false, index: true
      t.bigint :owner_id, index: true
      t.string :name, null: false
      t.bigint :monthly_salary_micros
      t.integer :performance_ratio, default: 10
      t.bigint :baseline_target_micros
      t.string :rank_note
      t.timestamps
    end
    add_foreign_key :crm_employee_comps, :users, column: :owner_id, on_delete: :nullify
  end
end
