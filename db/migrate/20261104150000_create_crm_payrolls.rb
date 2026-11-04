class CreateCrmPayrolls < ActiveRecord::Migration[7.1]
  def change
    # 月度工资表。一个月 + 一套模板 + 一个部门口径 = 一张表。
    create_table :crm_payroll_sheets do |t|
      t.references :account, null: false, index: true
      t.date :period_month, null: false          # 月份（取当月 1 号）
      t.string :template, null: false            # WORKSHOP 车间 / OFFICE 办公室+业务
      t.string :title                            # 「9月生产部工资表」这类
      t.string :status, null: false, default: 'DRAFT'  # DRAFT 核算中 / CONFIRMED 已确认
      t.bigint :created_by_id
      t.bigint :confirmed_by_id
      t.datetime :confirmed_at
      t.text :remark
      t.timestamps
    end
    add_index :crm_payroll_sheets, %i[account_id period_month template]

    # 每人一行。金额一律 micros。
    # ⚠️ user_id 可空：车间 38 人里 33 个在系统没账号，不能因为没账号就录不进来。
    create_table :crm_payroll_items do |t|
      t.references :account, null: false, index: true
      t.references :crm_payroll_sheet, null: false, index: { name: 'idx_payroll_items_on_sheet' }
      t.bigint :user_id, index: true
      t.string :employee_name, null: false       # 没账号的人就只有名字
      t.string :position
      t.string :employment_status                # 车间：「2021.3.2 正式员工」
      t.date :hire_date                          # 办公室：入职日期
      t.integer :sort_order, null: false, default: 0

      # 固定项
      t.bigint :base_total_micros,           null: false, default: 0  # 底薪合计（仅展示，不参与计算）
      t.bigint :basic_salary_micros,         null: false, default: 0
      t.bigint :position_allowance_micros,   null: false, default: 0
      t.bigint :seniority_allowance_micros,  null: false, default: 0  # 工龄补贴/其它
      t.bigint :meal_allowance_micros,       null: false, default: 0
      t.bigint :lodging_allowance_micros,    null: false, default: 0
      t.bigint :attendance_bonus_micros,     null: false, default: 0  # 全勤奖
      t.bigint :excellent_bonus_micros,      null: false, default: 0  # 优秀员工奖
      t.bigint :performance_salary_micros,   null: false, default: 0  # 绩效工资
      t.bigint :commission_salary_micros,    null: false, default: 0  # 提成工资

      # 加班
      t.decimal :weekday_ot_hours, precision: 8, scale: 2, null: false, default: 0
      t.bigint  :weekday_ot_rate_micros,     null: false, default: 0
      t.bigint  :weekday_ot_pay_micros,      null: false, default: 0
      t.decimal :weekend_ot_hours, precision: 8, scale: 2, null: false, default: 0
      t.bigint  :weekend_ot_rate_micros,     null: false, default: 0
      t.bigint  :weekend_ot_pay_micros,      null: false, default: 0

      # 出勤
      t.decimal :actual_days,   precision: 6, scale: 2, null: false, default: 0
      t.decimal :expected_days, precision: 6, scale: 2, null: false, default: 0
      t.decimal :leave_days,    precision: 6, scale: 2, null: false, default: 0
      t.bigint  :attendance_pay_micros, null: false, default: 0

      # 扣款
      t.bigint :late_deduction_micros,    null: false, default: 0
      t.bigint :absence_deduction_micros, null: false, default: 0  # 未打卡
      t.bigint :social_insurance_micros,  null: false, default: 0
      t.bigint :income_tax_micros,        null: false, default: 0

      # 结果（存下来，不每次现算：确认后的工资表是账，口径改了不该追溯改旧表）
      t.bigint :gross_pay_micros, null: false, default: 0
      t.bigint :net_pay_micros,   null: false, default: 0

      t.text :remark
      t.timestamps
    end
  end
end
