# 跟进记录来源：MANUAL=人工录入（默认），AI=AI 从邮件往来自动识别的进度。
# source_email_id 记录该 AI 进度来自哪封来信，用于幂等（同一封信不重复建记录）+ 溯源。
class AddSourceToCrmFollowUpNotes < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_follow_up_notes, :source, :string, null: false, default: 'MANUAL'
    add_column :crm_follow_up_notes, :source_email_id, :bigint
    add_index :crm_follow_up_notes, :source_email_id
  end
end
