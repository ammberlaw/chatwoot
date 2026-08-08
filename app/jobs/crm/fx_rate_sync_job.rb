# 每日抓取中国银行现汇买入价（外币订单折算人民币用）。全局汇率，无需按账号循环。
# 抓取失败不抛出——保证定时队列不因外部站点抖动而堆积。
class Crm::FxRateSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    count = Crm::BocFxRate.sync!
    Rails.logger.info("[Crm::FxRateSyncJob] 已更新中行汇率 #{count} 个币种")
  rescue StandardError => e
    Rails.logger.error("[Crm::FxRateSyncJob] #{e.class}: #{e.message}")
  end
end
