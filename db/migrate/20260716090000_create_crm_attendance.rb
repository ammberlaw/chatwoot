# 考勤模块一期：考勤规则（单行/账号）+ 每日打卡记录（每人每天一条）。
class CreateCrmAttendance < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_attendance_settings do |t|
      t.bigint :account_id, null: false, index: { unique: true }
      t.integer :work_days, array: true, null: false, default: [1, 2, 3, 4, 5] # 1=周一 … 7=周日
      t.string :clock_in_time, null: false, default: '09:00'
      t.string :clock_out_time, null: false, default: '18:00'
      t.integer :grace_minutes, null: false, default: 0

      t.timestamps
    end

    create_table :crm_attendance_records do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.date :work_date, null: false
      t.datetime :clock_in_at
      t.datetime :clock_out_at
      t.string :status, null: false, default: 'NORMAL'
      t.string :note
      t.bigint :adjusted_by_id

      t.timestamps
    end
    add_index :crm_attendance_records, [:account_id, :user_id, :work_date], unique: true, name: 'idx_crm_attendance_on_user_date'
    add_index :crm_attendance_records, [:account_id, :work_date]
  end
end
