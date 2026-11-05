# 每月 1 号把孤儿清单推给管理层（站内通知）。
# 复用 Mes::Notifier（账号内通用的站内通知，不限 MES）。
  # 不发邮件：这类清单是「有空再处理」的性质，邮件只会被归档；
# 而且 2026-09 有过四个人企业邮箱连续退信、预警实际送达 0 人的教训。
class Crm::OrphanAuditJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      sections = Crm::OrphanAuditService.new(account).call
      next if sections.empty?

      recipients = account.account_users.active_members
                          .select { |au| au.administrator? || au.crm_deputy_admin? }
                          .map(&:user_id)
      next if recipients.empty?

      total = sections.sum { |s| s[:rows].size }
      Mes::Notifier.notify(
        account: account, recipients: recipients, kind: 'orphan_audit',
        title: "月度体检：#{total} 项没人管的东西",
        body: sections.map { |s| "#{s[:title]}：#{s[:rows].size} 项\n  #{s[:rows].first(3).join("\n  ")}" }.join("\n\n")
      )
    rescue StandardError => e
      Rails.logger.warn("[OrphanAudit] account=#{account.id} 失败: #{e.message}")
    end
  end
end
