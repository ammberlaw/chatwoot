# 把 agent 这一轮建出来的邮件草稿认领给「触发它的那封来信」。
#
# 为什么必须打这个标记：草稿建完是躺在草稿箱里的，来信那一行上什么都不显示。
# 业务员打开邮箱看到客户来信，根本不知道系统已经替他写好回复了——等于白写。
# 列表靠 reply_to_email_id 显示「已预写回复」角标，点一下直接跳到那份草稿。
#
# 两个入口都要用，所以单独拎出来：
#   · Crm::AutoDraftReplyJob   老客户来信预写（走 draft_reply）
#   · Crm::InquiryTriageJob    新询盘初筛（走 draft_email，新开一封）
# 第一版只在前者里打了标记，初筛建的草稿在收件箱上看不见——同一个功能两种表现。
class Crm::AgentDraftLink
  # 只认这一轮刚建的：agent 跑一轮十几到几十秒，留足余量但别把人家手写的旧草稿也收编了。
  WINDOW = 10.minutes

  def self.claim(email)
    return if email.blank? || email.owner_id.blank?

    email.account.crm_emails
         .where(owner_id: email.owner_id, folder: 'DRAFT', reply_to_email_id: nil)
         .where(created_at: WINDOW.ago..)
         .update_all(reply_to_email_id: email.id, ai_drafted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    # 标记失败不该让整轮白跑：草稿还在草稿箱里，只是列表上少个角标。
    Rails.logger.warn("[agent draft link] email=#{email&.id}: #{e.class} #{e.message}")
  end
end
