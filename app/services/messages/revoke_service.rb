# 消息被撤回（WhatsApp 的「为所有人删除」）。入站（客户撤回他发的那条）和出站
# （业务员撤回自己发的）都走这里，保证两边落库形状一致。
#
# 原文不留：撤回后谁都看不到，和手机上一样。附件一并删掉，
# 否则撤回了还能从附件列表里把图翻出来。
#
# 同时打 deleted 标记：全站现成的「已删除消息」渲染、导出、搜索都认它，
# 撤回只是多一层「对方那边也没了」的语义，不用再铺一套。
class Messages::RevokeService
  CONTACT = 'contact'.freeze
  AGENT = 'agent'.freeze

  pattr_initialize [:message!, :by!]

  def perform
    # 重复撤回（手机和 CRM 同时点、桥重投同一条）当成功处理，别把 revoked_at 改掉。
    return message if message.content_attributes['revoked']

    ActiveRecord::Base.transaction do
      message.update!(
        # 语言按账号取，不靠 I18n.locale：客户撤回走的是桥的 webhook
        # （Webhooks::WhatsappWebController 不切账号语言），那条路径下 locale 还是默认的 en，
        # 落库就会写出一句英文，和业务员自己撤回的那条不一样。
        content: I18n.t('conversations.messages.revoked', locale: message.account.locale),
        content_type: :text,
        content_attributes: revoked_attributes
      )
      message.attachments.destroy_all
    end
    message
  end

  private

  # 只留「这条被谁撤回了」。原文、引用关系、表情回应都清掉——
  # 被撤回的消息在 WhatsApp 里是连带回应一起消失的。
  def revoked_attributes
    { 'deleted' => true, 'revoked' => true, 'revoked_by' => by.to_s, 'revoked_at' => Time.current.to_i }
  end
end
