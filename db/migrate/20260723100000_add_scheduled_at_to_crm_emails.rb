class AddScheduledAtToCrmEmails < ActiveRecord::Migration[7.1]
  # 定时发送：预约投递时间。send_status='SCHEDULED' 的邮件到点由分发任务转 PENDING 发送。
  def change
    add_column :crm_emails, :scheduled_at, :datetime
    add_index :crm_emails, [:send_status, :scheduled_at]
  end
end
