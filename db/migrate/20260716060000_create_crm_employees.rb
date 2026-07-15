# HR 员工主数据（员工档案）：身份/岗位/在职状态/薪酬发薪/联系方式/离职信息，
# 附件（入职资料、离职资料、证件照）走 ActiveStorage。
class CreateCrmEmployees < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_employees do |t|
      t.bigint :account_id, null: false, index: true
      # 基本身份
      t.string :employee_no, null: false
      t.string :name, null: false
      t.string :gender
      t.string :id_card_no
      t.date :birth_date
      t.string :native_place
      # 岗位与组织
      t.bigint :department_id
      t.string :job_title
      t.string :job_category
      t.string :work_location
      # 在职状态与关键日期
      t.string :status, null: false, default: 'PROBATION'
      t.date :hire_date
      t.date :regular_date
      t.integer :probation_months
      t.date :contract_start_date
      t.date :contract_end_date
      t.string :contract_type
      t.integer :renew_count
      # 薪酬与发薪
      t.string :salary_note
      t.string :bank_card_no
      t.string :bank_name
      # 联系方式
      t.string :phone
      t.string :email
      t.string :wechat
      # 离职信息
      t.date :resign_date
      t.text :resign_reason
      t.string :resign_type

      t.timestamps
    end
    add_index :crm_employees, [:account_id, :employee_no], unique: true
    add_index :crm_employees, [:account_id, :status]
  end
end
