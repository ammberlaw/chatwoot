# 午休时段：请假半天/整天的判定要扣掉它——12:00-13:30 的午休让上午(3h)和下午(4.5h)
# 不等长，不扣就会把「下午请假」判成整天假，直接算错考勤和工资。
# 空字符串 = 该组不设午休（保留旧行为）。
class AddBreakTimeToCrmAttendanceGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_attendance_groups, :break_start_time, :string, null: false, default: '12:00'
    add_column :crm_attendance_groups, :break_end_time, :string, null: false, default: '13:30'
  end
end
