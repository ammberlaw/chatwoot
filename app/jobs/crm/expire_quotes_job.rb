# 报价单有效期到期自动置 EXPIRED：每天把「未成交(DRAFT/SENT) 且 valid_until 已过」的报价标为失败态。
# CONFIRMED 报价不动（已确认的不因过期回退）。
class Crm::ExpireQuotesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Crm::Quote.pending
              .where('valid_until IS NOT NULL AND valid_until < ?', Time.zone.today.beginning_of_day)
              .update_all(status: 'EXPIRED', updated_at: Time.current)
  end
end
