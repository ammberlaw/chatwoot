# 考勤二期：审批模板可标记考勤联动类型（请假/补卡，审批通过自动写入考勤）；考勤规则增加节假日列表。
class AddAttendanceLinkage < ActiveRecord::Migration[7.1]
  def change
    add_column :oa_approval_templates, :attendance_kind, :string
    add_column :crm_attendance_settings, :holidays, :string, array: true, null: false, default: []
  end
end
