# 按桥给的地址在某个 WhatsApp 个人号收件箱里找到对应的 CRM 联系人。
#
# 桥报上来的地址可能是 LID（…@lid）也可能是手机号 JID（…@s.whatsapp.net），而 CRM 的
# source_id 是这个会话建档时用的那一个（线上几乎全是 LID，同一个人两种写法都见得到）。
# 所以把拿到的几种写法都试一遍，最后再按手机号在本收件箱内兜一次。
module Whatsapp::WebContactLookup
  module_function

  def contact_inbox(inbox, entry)
    ids = [entry[:source_id], entry[:id], entry[:lid]].filter_map { |v| v.presence&.to_s }.uniq
    ci = inbox.contact_inboxes.where(source_id: ids).first if ids.any?
    ci || by_phone(inbox, entry[:phone])
  end

  def by_phone(inbox, phone)
    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    inbox.contact_inboxes.joins(:contact).find_by(contacts: { phone_number: "+#{digits}" })
  end
end
