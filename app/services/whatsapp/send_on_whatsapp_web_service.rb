class Whatsapp::SendOnWhatsappWebService < Base::SendOnChannelService
  private

  def channel_class
    Channel::WhatsappWeb
  end

  def perform_reply
    return if message.attachments.blank? && message.outgoing_content.blank?

    # source_id is the WhatsApp JID (classic phone or LID); the bridge sends to it verbatim.
    jid = message.conversation.contact_inbox.source_id
    message_id = message.attachments.any? ? send_attachments(jid) : send_text(jid)
    message.update!(source_id: message_id) if message_id.present?
  rescue Whatsapp::BaileysBridgeClient::BridgeError => e
    message.update!(status: :failed, external_error: e.message)
  end

  def send_text(jid)
    client.send_text(channel.session_key, jid, message.outgoing_content)
  end

  # 多个附件逐个发；正文只跟着第一个当图注，免得每张图下面都重复一遍同样的话。
  # 回存第一条的 message_id 作为本条消息的 source_id（回执按它匹配）。
  def send_attachments(jid)
    first_id = nil
    message.attachments.each_with_index do |attachment, index|
      sent = client.send_media(channel.session_key, jid,
                               url: attachment.download_url,
                               filename: attachment.file.filename.to_s,
                               mimetype: attachment.file.content_type,
                               caption: index.zero? ? message.outgoing_content.presence : nil)
      first_id ||= sent
    end
    first_id
  end

  def client
    @client ||= Whatsapp::BaileysBridgeClient.new
  end
end
