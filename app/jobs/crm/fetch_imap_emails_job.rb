# 定时收信：遍历所有启用 IMAP 的业务员邮箱，逐个拉取新邮件落 CRM 收件箱。
# 单个账户失败不影响其余（记日志继续）。由 schedule.yml 每 5 分钟触发。
class Crm::FetchImapEmailsJob < ApplicationJob
  queue_as :low

  def perform(mail_account_id = nil)
    accounts = mail_account_id ? Crm::MailAccount.imap_active.where(id: mail_account_id) : Crm::MailAccount.imap_active
    accounts.find_each do |mail_account|
      Crm::ImapFetchService.new(mail_account: mail_account).perform
    rescue StandardError => e
      Rails.logger.error("[Crm::FetchImapEmails] account=#{mail_account.id} failed: #{e.message}")
    end
  end
end
