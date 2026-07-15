# 考勤组：不同人群不同考勤规则（工作日/上下班时间/宽限/节假日/成员）。
# 存量单一规则迁移为「默认考勤组」；未分组成员自动按默认组执行。
class CreateCrmAttendanceGroups < ActiveRecord::Migration[7.1]
  def up
    create_table :crm_attendance_groups do |t|
      t.bigint :account_id, null: false, index: true
      t.string :name, null: false
      t.boolean :is_default, null: false, default: false
      t.integer :work_days, array: true, null: false, default: [1, 2, 3, 4, 5]
      t.string :clock_in_time, null: false, default: '09:00'
      t.string :clock_out_time, null: false, default: '18:00'
      t.integer :grace_minutes, null: false, default: 0
      t.string :holidays, array: true, null: false, default: []
      t.bigint :user_ids, array: true, null: false, default: []

      t.timestamps
    end

    # 存量规则 → 默认考勤组
    execute <<~SQL.squish
      INSERT INTO crm_attendance_groups
        (account_id, name, is_default, work_days, clock_in_time, clock_out_time, grace_minutes, holidays, created_at, updated_at)
      SELECT account_id, '默认考勤组', TRUE, work_days, clock_in_time, clock_out_time, grace_minutes, holidays, NOW(), NOW()
      FROM crm_attendance_settings
    SQL

    drop_table :crm_attendance_settings
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
