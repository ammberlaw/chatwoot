class AddExtraWorkdaysToAttendanceGroups < ActiveRecord::Migration[7.1]
  # 调休补班：把某些本该休息的日子（如周六）标为上班日。与 holidays（额外休息日）互补。
  def change
    add_column :crm_attendance_groups, :extra_workdays, :string, array: true, default: [], null: false
  end
end
