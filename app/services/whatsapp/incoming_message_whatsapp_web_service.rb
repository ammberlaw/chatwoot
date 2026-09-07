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
        message_type: :incoming,
        sender: @contact,
        source_id: message_id
      )
    end
  end

  private

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
