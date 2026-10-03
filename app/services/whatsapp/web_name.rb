# WhatsApp 个人号联系人「名字」的共同判断。入站消息、历史导入、联系人同步三条路
# 都要判「现在这个名字是不是占位」，散开写过一次就会各自漂移，收在这里。
module Whatsapp::WebName
  module_function

  # 占位名：空、等于 JID、或纯粹是号码/JID 的数字串（真名不会长这样）。
  def placeholder?(value, source_id = nil)
    v = value.to_s.strip
    return true if v.blank?
    return true if source_id.present? && v == source_id.to_s

    v.match?(/\A\+?\d[\d\s@.a-z]*\z/i)
  end
end
