# Turns an inbound message forwarded by the Baileys bridge into a Chatwoot
# contact + conversation + message. Mirrors the Telegram incoming flow.
# 单聊：文字 + 媒体（图片/视频/语音/文件）。群聊仍不收。
class Whatsapp::IncomingMessageWhatsappWebService
  include FileTypeHelper

  pattr_initialize [:inbox!, :params!]

  def perform
    # 纯媒体消息没有文字，只判 text 会把客户发来的图片/视频整条丢掉。
    return if params[:text].blank? && media_blob.nil?

    # WhatsApp can redeliver the same message; the message id is stable per message.
    # Serialize the check-then-create so two concurrent identical webhooks can't both
    # pass the dedup check and insert duplicates (advisory lock releases at tx end).
    with_message_lock do
      next if message_id.present? && inbox.messages.exists?(source_id: message_id)

      set_contact
      set_conversation
      attach_media(build_message)
    end
  end

  private

  def build_message
    @conversation.messages.create!(
      content: params[:text],
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: from_me? ? :outgoing : :incoming,
      sender: from_me? ? agent : @contact,
      source_id: message_id,
      created_at: sent_at,
      content_attributes: reply_attributes
    )
  end

  # 客户引用我们某条消息回复时，桥带来被引用那条的 WhatsApp id。写进
  # in_reply_to_external_id，Message#ensure_in_reply_to 会据此找到本地那条、
  # 补上 in_reply_to，气泡上方就显示出被引用的原文（和邮件、Telegram 同一套渲染）。
  # 被引用的消息不在 CRM 里（配对前的老消息）也不要紧：补不上就只是不显示引用。
  def reply_attributes
    quoted = params[:quoted_id].presence
    quoted ? { in_reply_to_external_id: quoted } : {}
  end

  # 控制器已把上传的文件落成 blob，这里只按 signed_id 取回来挂到消息上。
  # 取不到就当没有媒体（blob 过期/被清理），消息本身照常存在。
  def media_blob
    return @media_blob if defined?(@media_blob)

    signed_id = params[:media_signed_id].presence
    @media_blob = signed_id && ActiveStorage::Blob.find_signed(signed_id)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_web] 取入站媒体 blob 失败：#{e.class} #{e.message}")
    @media_blob = nil
  end

  # file_type 决定前端怎么渲染（图片/视频直接预览，其余按文件下载）。
  def attach_media(message)
    blob = media_blob
    return if blob.nil?

    attachment = message.attachments.create!(
      account_id: inbox.account_id,
      file_type: file_type(blob.content_type)
    )
    attachment.file.attach(blob)
  end

  # 业务员在手机 WhatsApp 里直接回的消息（桥带 from_me）也要进 CRM，记成「我方发出」，
  # 否则会话里只剩客户单边说话。从 CRM 发出的那条按 source_id 判重，不会重复落。
  def from_me?
    ActiveModel::Type::Boolean.new.cast(params[:from_me]).present?
  end

  # 我方消息的发送人记成该收件箱的归属业务员（个人号收件箱只有他本人是成员）。
  def agent
    @agent ||= inbox.inbox_members.first&.user
  end

  # 按消息在 WhatsApp 上的真实时间落库：历史补收和手机端补投的消息不能堆在收件那一刻，
  # 否则客户「最后互动时间」和流失预警都会算错。
  def sent_at
    ts = params[:timestamp].presence&.to_i
    ts&.positive? ? Time.zone.at(ts) : Time.current
  end

  def message_id
    params[:message_id].presence&.to_s
  end

  def with_message_lock
    ActiveRecord::Base.transaction do
      if message_id.present?
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            ['SELECT pg_advisory_xact_lock(hashtext(?))', "wa_web:#{inbox.id}:#{message_id}"]
          )
        )
      end
      yield
    end
  end

  # The routing key is the WhatsApp JID (classic phone or opaque LID). We reply to it verbatim.
  def source_id
    params[:source_id].presence&.to_s || params[:from].to_s
  end

  def set_contact
    contact_attributes = { name: params[:name].presence || source_id }
    # Only set a real phone number when we actually know it; never store the opaque LID.
    contact_attributes[:phone_number] = "+#{params[:phone]}" if params[:phone].present?

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: source_id,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform
    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
    sync_contact_name
  end

  # 联系人名字只在「首次建档」时写入，之后再来的消息不会改它。于是「自己先发话」的会话
  # 会永久卡着一串 JID 数字当名字（历史导入特别常见，自己发的消息带不了对方名字），
  # 而且对方后来改了昵称、业务员在手机上加了备注，CRM 这边都看不到。
  # 统一交给 WebContactSync 按来源可靠性决定要不要覆盖（人工在 CRM 改过的名字不动）。
  def sync_contact_name
    entry = { source_id: source_id, phone: params[:phone], book_name: params[:book_name], notify: params[:name] }
    Whatsapp::WebContactSync.new(inbox: inbox, entries: [entry]).perform
  end

  def set_conversation
    @conversation = if inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    )
  end
end
