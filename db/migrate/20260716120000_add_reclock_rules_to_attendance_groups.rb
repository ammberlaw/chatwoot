# 补卡规则（按考勤组）：每月补卡次数上限（0=不允许补卡）、可补卡时限天数（0=不限）。
class AddReclockRulesToAttendanceGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_attendance_groups, :reclock_limit, :integer, null: false, default: 3
    add_column :crm_attendance_groups, :reclock_window_days, :integer, null: false, default: 30
  end
end
