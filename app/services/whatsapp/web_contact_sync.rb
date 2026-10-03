# 把桥推来的 WhatsApp 联系人资料（手机通讯录备注名 / 对方自设名）同步到 CRM 联系人。
#
# 名字有三个来源，可靠性从高到低：
#   book  = 业务员自己手机通讯录里存的备注名（Baileys 的 contact.name）——最准，业务认的就是这个
#   push  = 对方自己设的 WhatsApp 昵称（contact.notify / 消息里的 pushName）——会变、可能是广告词
#   占位   = JID 或光一串号码
#
# 覆盖规则（关键是别踩业务在 CRM 里手动改过的名字）：
#   · 当前名字是占位 → 来什么都写
#   · 当前名字正是上次我们从 WhatsApp 写进去的那个 → 可以更新（记在 wa_name 里认领）
#   · 其它情况（人工改过）→ 一律不动
#   · 另外 push 永不覆盖 book，免得备注名被对方改昵称顶掉
class Whatsapp::WebContactSync
  BOOK = 'book'.freeze
  PUSH = 'push'.freeze

  pattr_initialize [:inbox!, :entries!]

  def perform
    Array(entries).each do |raw|
      entry = raw.respond_to?(:with_indifferent_access) ? raw.with_indifferent_access : raw
      sync_one(entry)
    rescue StandardError => e
      Rails.logger.warn("[wa_contact_sync] inbox=#{inbox.id} #{entry.inspect[0, 120]}: #{e.class} #{e.message}")
    end
  end

  private

  def sync_one(entry)
    name, source = pick_name(entry)
    return if name.blank?

    contact = resolve_contact(entry)
    return if contact.nil?

    apply_name(contact, name, source)
  end

  # book 优先；两者都没有就不动。
  def pick_name(entry)
    book = clean(entry[:book_name] || entry[:name])
    return [book, BOOK] if book.present?

    [clean(entry[:notify] || entry[:push_name]), PUSH]
  end

  def clean(value)
    v = value.to_s.strip
    return nil if v.blank?

    v.truncate(ApplicationRecord::MAX_STRING_COLUMN_LENGTH, omission: '')
  end

  def resolve_contact(entry)
    Whatsapp::WebContactLookup.contact_inbox(inbox, entry)&.contact
  end

  def apply_name(contact, name, source)
    attrs = contact.additional_attributes || {}
    return unless overwritable?(contact, attrs, source)
    return if contact.name == name

    contact.update!(name: name)
    # update_columns：additional_attributes 只是来源账本，不必再跑一遍头像等校验。
    contact.update_columns(additional_attributes: attrs.merge('wa_name' => name, 'wa_name_source' => source)) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info("[wa_contact_sync] inbox=#{inbox.id} contact=#{contact.id} <- #{source} #{name}")
  end

  def overwritable?(contact, attrs, source)
    placeholder = Whatsapp::WebName.placeholder?(contact.name)
    return true if placeholder
    # 对方改昵称不许顶掉手机里的备注名。
    return false if source == PUSH && attrs['wa_name_source'] == BOOK

    contact.name == attrs['wa_name']
  end
end
