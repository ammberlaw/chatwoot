# 自动给「像买家」的线索跑背调。
#
# 为什么要自动：背调出来的东西（主营、可能采购什么、欧盟税号验证）恰恰是
# 业务员判断要不要跟的依据，手动一条条点太费事。
# 为什么不在搜索里同步做：一次 20~38 秒，一屏十条就得等五六分钟。
#
# ⚠️ **一家公司一个 job**，别写成「一个 job 跑几十家」：
# 那样一个任务会占着 Sidekiq 线程半小时不放，发信、收信全被它堵在后面
# （和 2026-08 那次发信卡「发送中」是同一类事故）。
class Crm::LeadBgCheckJob < ApplicationJob
  # ⚠️ 默认走 deferred，**不要放 low**。
  # low 队列上挂着 crm/fetch_imap_emails_job（每分钟收一次邮件）和
  # webhooks/whatsapp_events_job（WhatsApp 入站消息）——一次背调占着线程 17~30 秒，
  # 一个任务排 60 个就是半小时，收信和 WhatsApp 全排它后面。
  # 2026-08 发信卡「发送中」就是这个形态（IMAP 卡 90 秒拖垮 Sidekiq）。
  # 背调晚几分钟没人在意，邮件晚几分钟是事故。
  #
  # 业务员手动点的那次走 low（见 leads_controller#ai_bg_check）：
  # 一次只有一个，而且人在等着看结果。
  queue_as :deferred

  def perform(lead_id)
    lead = Crm::Lead.find_by(id: lead_id)
    return if lead.nil? || lead.domain.blank?
    # 同一家公司可能排了好几条（几个联系人各一条），先跑完的那条已经把结果
    # 盖到全公司了，后面的直接跳过，不重复抓官网。
    return if lead.reload.raw['bg'].present?

    Crm::LeadBackgroundCheck.new(lead: lead).call
  rescue StandardError => e
    Rails.logger.warn("[LeadBgCheck] lead=#{lead_id}: #{e.class} #{e.message}")
  ensure
    # 失败也要清，否则那条线索会永远停在「背调中…」。
    clear_running(lead_id)
  end

  private

  def clear_running(lead_id)
    lead = Crm::Lead.find_by(id: lead_id)
    return if lead.nil? || lead.raw['bg_running_at'].blank?

    lead.update_columns(raw: lead.raw.except('bg_running_at')) # rubocop:disable Rails/SkipsModelValidations
  end
end
