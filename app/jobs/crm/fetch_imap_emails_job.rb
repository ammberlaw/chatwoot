# 定时收信（每分钟由 schedule.yml 触发）。
# 无参调用 = 调度入口：给每个启用收件的账户各扇出一个独立子 job 并发拉取；
# 带 mail_account_id = 子 job：只拉这一个账户。
# 扇出的意义：单账户连不上/超时（如被 GFW 墙的 Gmail、首拉大回溯）只拖它自己这一个 job，
# 不再像早先串行遍历那样一个死号拖慢全队收信。
class Crm::FetchImapEmailsJob < ApplicationJob
  queue_as :low

  def perform(mail_account_id = nil)
    return fetch_one(mail_account_id) if mail_account_id

    Crm::MailAccount.imap_active.pluck(:id).each { |id| Crm::FetchImapEmailsJob.perform_later(id) }
  end

  private

  def fetch_one(mail_account_id)
    mail_account = Crm::MailAccount.imap_active.find_by(id: mail_account_id)
    return unless mail_account

    service = mail_account.pop3? ? Crm::PopFetchService : Crm::ImapFetchService
    service.new(mail_account: mail_account).perform
  rescue StandardError => e
    Rails.logger.error("[Crm::FetchImapEmails] account=#{mail_account_id} failed: #{e.message}")
  end
end
