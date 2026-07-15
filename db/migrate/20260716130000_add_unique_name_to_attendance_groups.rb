# 考勤组名唯一（账号内）。
class AddUniqueNameToAttendanceGroups < ActiveRecord::Migration[7.1]
  def change
    add_index :crm_attendance_groups, [:account_id, :name], unique: true
  end
end
