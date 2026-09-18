# 配对时 WhatsApp 推来的历史消息批次入库。
#
# 全量导入：个人号里聊过的每个人都进来，不按「是不是已建档客户」筛。
# （曾按手机号匹配 CRM 客户筛过，但迁入的客户九成没填电话——12430 个里只有 43 个有——
#  筛下来几乎一条都不剩，等于没导。业务要的是完整历史，宁可多不可漏。）
#
# 群聊 / 状态 / 频道 / 纯媒体消息在桥那侧已经过滤掉，到这里的都是个人聊天的文字消息。
# 逐条落库复用 IncomingMessageWhatsappWebService：方向、原始时间戳、按 message_id 判重
# 都在那里，历史与实时同一条路径，不会重复也不会错位。
class Webhooks::WhatsappWebHistoryJob < ApplicationJob
  queue_as :low

  def perform(payload)
    inbox = Inbox.find_by(id: payload['inbox_id'])
    return if inbox&.channel_type != 'Channel::WhatsappWeb'

    messages = Array(payload['messages'])
    return if messages.empty?

    Current.account = inbox.account
    ok = messages.count { |m| import_one(inbox, m) }
    Rails.logger.info("[WA history] inbox=#{inbox.id} 收到 #{messages.size} 条，入库 #{ok} 条")
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
end
