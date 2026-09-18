# 配对时 WhatsApp 推来的历史消息批次入库。
#
# 只导「已经是我们客户」的会话——业务员的个人号里混着家人朋友群聊（实测一个号 899 个会话），
# 全导会把几百个非客户灌进客户库。判定口径两条，命中任一即导：
#   1. 这个 JID 在本收件箱已经有会话（绑定后聊过的人，正是要补齐对话的那批）
#   2. 手机号能对上某个 CRM 客户的联系电话 / WhatsApp 号
#
# 逐条落库复用 IncomingMessageWhatsappWebService：方向、原始时间戳、按 message_id 判重
# 都在那里，历史与实时同一条路径，不会重复也不会错位。
class Webhooks::WhatsappWebHistoryJob < ApplicationJob
  queue_as :low

  # 电话归一：只留数字，再剥中国号的 86/0086 前缀（与客户查重同口径）。
  PHONE_NORM_SQL = "NULLIF(REGEXP_REPLACE(REGEXP_REPLACE(COALESCE(%s, ''), '\\D', '', 'g'), '^(00)?86(1\\d{10})$', '\\2'), '')".freeze

  def perform(payload)
    inbox = Inbox.find_by(id: payload['inbox_id'])
    return if inbox&.channel_type != 'Channel::WhatsappWeb'

    messages = Array(payload['messages'])
    return if messages.empty?

    Current.account = inbox.account
    known = known_source_ids(inbox, messages)
    imported = messages.count { |m| import_one(inbox, m) if known.include?(m['source_id'].to_s) }
    Rails.logger.info("[WA history] inbox=#{inbox.id} 收到 #{messages.size} 条，命中客户 #{imported} 条")
  ensure
    Current.account = nil
  end

  private

  def import_one(inbox, msg)
    Whatsapp::IncomingMessageWhatsappWebService.new(inbox: inbox, params: msg.with_indifferent_access).perform
    true
  rescue StandardError => e
    Rails.logger.warn("[WA history] inbox=#{inbox.id} msg=#{msg['message_id']}: #{e.class} #{e.message}")
    false
  end

  # 本批里「该导」的 JID 集合：本收件箱已有会话的，加上手机号能对上 CRM 客户的。
  def known_source_ids(inbox, messages)
    by_jid = messages.index_by { |m| m['source_id'].to_s }
    existing = inbox.contact_inboxes.where(source_id: by_jid.keys).pluck(:source_id).to_set
    pending = by_jid.reject { |jid, _| existing.include?(jid) }
    existing + matched_by_phone(pending)
  end

  def matched_by_phone(pending)
    phones = pending.filter_map { |_, m| normalize(m['phone']) }.uniq
    return Set.new if phones.empty?

    hit = Current.account.crm_customers
                 .where("#{format(PHONE_NORM_SQL, 'contact_phone')} IN (:p) OR #{format(PHONE_NORM_SQL, 'whats_app')} IN (:p)", p: phones)
                 .pluck(Arel.sql("#{format(PHONE_NORM_SQL, 'contact_phone')}, #{format(PHONE_NORM_SQL, 'whats_app')}"))
                 .flatten.compact.to_set
    pending.filter_map { |jid, m| jid if hit.include?(normalize(m['phone'])) }.to_set
  end

  def normalize(phone)
    digits = phone.to_s.gsub(/\D/, '')
    digits.sub(/\A(00)?86(1\d{10})\z/, '\2').presence
  end
end
