# Turns an inbound message forwarded by the Baileys bridge into a Chatwoot
# contact + conversation + message. Mirrors the Telegram incoming flow.
# Slice 1: individual text chats only.
class Whatsapp::IncomingMessageWhatsappWebService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if params[:text].blank?

    # WhatsApp can redeliver the same message; the message id is stable per message.
    # Serialize the check-then-create so two concurrent identical webhooks can't both
    # pass the dedup check and insert duplicates (advisory lock releases at tx end).
    with_message_lock do
      next if message_id.present? && inbox.messages.exists?(source_id: message_id)

      set_contact
      set_conversation
      @conversation.messages.create!(
        content: params[:text],
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        message_type: from_me? ? :outgoing : :incoming,
        sender: from_me? ? agent : @contact,
        source_id: message_id,
        created_at: sent_at
      )
    end
  end

  private

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
