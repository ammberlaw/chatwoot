class Whatsapp::SendOnWhatsappWebService < Base::SendOnChannelService
  private

  def channel_class
    Channel::WhatsappWeb
  end

  def perform_reply
    return if message.outgoing_content.blank?

    # source_id is the WhatsApp JID (classic phone or LID); the bridge sends to it verbatim.
    jid = message.conversation.contact_inbox.source_id
    message_id = Whatsapp::BaileysBridgeClient.new.send_text(channel.session_key, jid, message.outgoing_content)
    message.update!(source_id: message_id) if message_id.present?
  rescue Whatsapp::BaileysBridgeClient::BridgeError => e
    message.update!(status: :failed, external_error: e.message)
  end
end
