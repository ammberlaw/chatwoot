class AddFieldAndSourceToAttendance < ActiveRecord::Migration[7.1]
  # field：把「外勤」持久化，避免下班打卡重算把 FIELD 洗掉。
  # source：记录来源（clock 打卡 / hr HR修正 / approval 审批联动），用于覆盖优先级——
  #   HR 手工修正优先，审批联动不覆盖 HR。存量已修正记录回填 source='hr'。
  # 考勤组 is_default 加部分唯一索引，保证每账号仅一个默认组（消除并发建默认组竞态）。
  def up
    add_column :crm_attendance_records, :field, :boolean, default: false, null: false
    add_column :crm_attendance_records, :source, :string, default: 'clock', null: false

    execute("UPDATE crm_attendance_records SET source = 'hr' WHERE adjusted_by_id IS NOT NULL")
    execute("UPDATE crm_attendance_records SET field = TRUE WHERE status = 'FIELD'")

    # 存量若同账号存在多个默认组，仅保留最小 id 者，其余降级，才能建唯一索引。
    execute(<<~SQL.squish)
      UPDATE crm_attendance_groups g SET is_default = FALSE
      WHERE is_default = TRUE
        AND id > (SELECT MIN(g2.id) FROM crm_attendance_groups g2
                  WHERE g2.account_id = g.account_id AND g2.is_default = TRUE)
    SQL

    add_index :crm_attendance_groups, :account_id, unique: true, where: 'is_default',
              name: 'idx_crm_attendance_groups_single_default'
  end

  def down
    remove_index :crm_attendance_groups, name: 'idx_crm_attendance_groups_single_default'
    remove_column :crm_attendance_records, :source
    remove_column :crm_attendance_records, :field
  end
end
