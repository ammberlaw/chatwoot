# 定时发送分发：把到点的定时邮件（SCHEDULED 且 scheduled_at 已到）转为 PENDING，
# 由 Crm::Email 的 after_commit 回调入队 Crm::SendEmailJob 走正常 SMTP 发送。
# 由 schedule.yml 每分钟触发。
class Crm::DispatchScheduledEmailsJob < ApplicationJob
  queue_as :medium

  def perform
    Crm::Email.where(send_status: 'SCHEDULED')
              .where('scheduled_at <= ?', Time.current)
              .find_each do |email|
      email.update!(send_status: 'PENDING')
    rescue StandardError => e
      Rails.logger.error("[Crm::DispatchScheduledEmails] email=#{email.id} failed: #{e.message}")
    end
  end
end
