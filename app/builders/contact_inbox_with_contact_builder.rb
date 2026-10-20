# This Builder will create a contact and contact inbox with specified attributes.
# If an existing identified contact exisits, it will be returned.
# for contact inbox logic it uses the contact inbox builder

class ContactInboxWithContactBuilder
  pattr_initialize [:inbox!, :contact_attributes!, :source_id, :hmac_verified]

  def perform
    find_or_create_contact_and_contact_inbox
  # in case of race conditions where contact is created by another thread
  # we will try to find the contact and create a contact inbox
  rescue ActiveRecord::RecordNotUnique
    find_or_create_contact_and_contact_inbox
  end

  def find_or_create_contact_and_contact_inbox
    @contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id) if source_id.present?
    return @contact_inbox if @contact_inbox

    ActiveRecord::Base.transaction(requires_new: true) do
      build_contact_with_contact_inbox
    end
    update_contact_avatar(@contact) unless @contact.avatar.attached?
    @contact_inbox
  end

  private

  def build_contact_with_contact_inbox
    @contact = find_contact || create_contact
    @contact_inbox = create_contact_inbox
  end

  def account
    @account ||= inbox.account
  end

  def create_contact_inbox
    ContactInboxBuilder.new(
      contact: @contact,
      inbox: @inbox,
      source_id: @source_id,
      hmac_verified: hmac_verified
    ).perform
  end

  def update_contact_avatar(contact)
    ::Avatar::AvatarFromUrlJob.perform_later(contact, contact_attributes[:avatar_url]) if contact_attributes[:avatar_url]
  end

  def create_contact
    account.contacts.create!(
      name: contact_name,
      phone_number: contact_attributes[:phone_number],
      email: contact_attributes[:email],
      identifier: contact_attributes[:identifier],
      additional_attributes: contact_attributes[:additional_attributes],
      custom_attributes: contact_attributes[:custom_attributes]
    )
  end

  def contact_name
    name = contact_attributes[:name] || ::Haikunator.haikunate(1000)
    name.truncate(ApplicationRecord::MAX_STRING_COLUMN_LENGTH, omission: '')
  end

  def find_contact
    contact = find_contact_by_identifier(contact_attributes[:identifier])
    contact ||= find_contact_by_email(contact_attributes[:email])
    contact ||= find_contact_by_phone_number(contact_attributes[:phone_number])
    contact ||= find_contact_by_instagram_source_id(source_id) if instagram_channel?
    contact ||= find_contact_by_whatsapp_source_id(source_id) if whatsapp_channel?

    contact
  end

  def instagram_channel?
    inbox.channel_type == 'Channel::Instagram'
  end

  WHATSAPP_CHANNELS = %w[Channel::Whatsapp Channel::WhatsappWeb].freeze

  def whatsapp_channel?
    WHATSAPP_CHANNELS.include?(inbox.channel_type)
  end

  # 同一个人发给公司不同 WhatsApp 线（官方号 / 各业务员的个人号）时复用同一条联系人。
  #
  # 原来只按手机号对。但个人号那条链路入站**可能只给 LID**（WhatsApp 的匿名标识，
  # 形如 220486558580954@lid）、拿不到手机号，于是同一个客户在第二条线上
  # 又建出一条新联系人——生产上 Pocketprice 就是这样成了 29138 / 29150 两条，
  # 两条会话各走各的，业务看着像「系统里发的和手机上发的不同步」。
  # （同一个客户 BLOOM OIL 因为有手机号能对上，就只有一条，表现正常。）
  #
  # 按 source_id 对是安全的：LID 和手机号 JID 都唯一标识一个 WhatsApp 账号，
  # 不存在两个人共用同一个的情况。
  # 只合并**联系人**，contact_inbox 仍是一线一条——每条线的会话本来就该分开，
  # 客户手机上看到的也是两个不同号码的对话。
  def find_contact_by_whatsapp_source_id(wa_source_id)
    return if wa_source_id.blank?

    ContactInbox.joins(:inbox)
                .where(source_id: wa_source_id)
                .where(inboxes: { account_id: account.id, channel_type: WHATSAPP_CHANNELS })
                .first&.contact
  end

  # There might be existing contact_inboxes created through Channel::FacebookPage
  # with the same Instagram source_id. New Instagram interactions should create fresh contact_inboxes
  # while still reusing contacts if found in Facebook channels so that we can create
  # new conversations with the same contact.
  def find_contact_by_instagram_source_id(instagram_id)
    return if instagram_id.blank?

    existing_contact_inbox = ContactInbox.joins(:inbox)
                                         .where(source_id: instagram_id)
                                         .where(
                                           'inboxes.channel_type = ? AND inboxes.account_id = ?',
                                           'Channel::FacebookPage',
                                           account.id
                                         ).first

    existing_contact_inbox&.contact
  end

  def find_contact_by_identifier(identifier)
    return if identifier.blank?

    account.contacts.find_by(identifier: identifier)
  end

  def find_contact_by_email(email)
    return if email.blank?

    account.contacts.from_email(email)
  end

  def find_contact_by_phone_number(phone_number)
    return if phone_number.blank?

    account.contacts.find_by(phone_number: phone_number)
  end
end
