# 桥推来的联系人资料（手机通讯录备注名 / 对方自设昵称）批量同步。
# 一批可能是业务员整本通讯录几百条，放后台做，别卡住桥。
class Webhooks::WhatsappWebContactsJob < ApplicationJob
  queue_as :low

  def perform(payload)
    inbox = Inbox.find_by(id: payload['inbox_id'])
    return if inbox&.channel_type != 'Channel::WhatsappWeb'

    entries = Array(payload['contacts'])
    return if entries.empty?

    Current.account = inbox.account
    Whatsapp::WebContactSync.new(inbox: inbox, entries: entries).perform
  ensure
    Current.account = nil
  end
end
