# 把桥下载好的 WhatsApp 头像字节挂到 CRM 联系人上。
#
# 为什么是桥下载、而不是把 URL 交给 Avatar::AvatarFromUrlJob：头像在 pps.whatsapp.net 上，
# 生产机（深圳）连不通那个域（实测 curl 直接超时），只有香港桥能取。所以桥取完字节 multipart
# 传过来，这边只负责落盘。
class Whatsapp::WebAvatarSync
  MAX_BYTES = 5.megabytes
  ALLOWED_TYPES = Avatarable::ALLOWED_AVATAR_CONTENT_TYPES

  pattr_initialize [:inbox!, :entry!, :file!]

  def perform
    contact = Whatsapp::WebContactLookup.contact_inbox(inbox, entry)&.contact
    return :no_contact if contact.nil?
    return :unchanged if unchanged?(contact)

    return :rejected unless acceptable?

    attach(contact)
    :ok
  end

  private

  # 头像没换就别反复写（ActiveStorage 每次 attach 都会新建 blob + 变体，白占磁盘）。
  def unchanged?(contact)
    digest.present? &&
      (contact.additional_attributes || {})['wa_avatar_hash'] == digest &&
      contact.avatar.attached?
  end

  def digest
    @digest ||= entry[:img_hash].presence&.to_s
  end

  def acceptable?
    size = file.size.to_i
    type = file.content_type.to_s.split(';').first
    return log_reject("size=#{size}") if size.zero? || size > MAX_BYTES
    return log_reject("type=#{type}") unless ALLOWED_TYPES.include?(type)

    true
  end

  def log_reject(reason)
    Rails.logger.warn("[wa_avatar] 丢弃头像 inbox=#{inbox.id} #{reason}")
    false
  end

  def attach(contact)
    contact.avatar.attach(
      io: file.tempfile,
      filename: file.original_filename.presence || 'whatsapp-avatar.jpg',
      content_type: file.content_type.to_s.split(';').first
    )
    attrs = (contact.additional_attributes || {}).merge('wa_avatar_hash' => digest, 'wa_avatar_synced_at' => Time.current.iso8601)
    contact.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
  end
end
