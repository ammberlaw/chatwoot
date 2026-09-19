# 会话可见性的**唯一口径**：列表过滤（ConversationFinder → PermissionFilterService）、
# 单条鉴权（ConversationPolicy）、实时推送（ActionCableListener）三处共用。
#
# ⚠️ 三处必须走同一套判定。散开写迟早走岔，走岔就是漏：列表里看不到、直接开链接却能看（IDOR）；
# 或者列表里看不到、新消息却一直推到他浏览器里。
#
# 规则（2026-09-19 定）：
# - 管理员看全部（调用方自己短路，不进这里）。
# - **公司公共号**（WhatsApp Cloud API 这类多人共用的收件箱）：只看**分到自己头上**的那几条。
#   是收件箱成员不等于能看全箱——公司号 15 个成员全是业务员，按 Chatwoot 原生口径
#   等于每个业务员都看得见全公司的客户会话。
# - **个人号收件箱**：业务员自己绑的 WhatsApp 号，整箱都看得见。那是他自己的号，
#   哪怕某条转给同事协办，他也该看得见。
# - 被同事拉进来当**对话参与者**的那几条，不论在哪个收件箱都看得见（协办的前提）。
module Conversations::Visibility
  # 个人号＝Baileys 桥接的 WhatsApp Web 号：一号一箱、只有本人是成员
  # （见 Api::V1::Accounts::Crm::WhatsappWebController）。
  PERSONAL_CHANNEL_TYPE = 'Channel::WhatsappWeb'.freeze

  module_function

  # 我名下的个人号收件箱 id（子查询，供 where 直接用）。
  def personal_inbox_ids(user, account)
    user.inboxes.where(account_id: account&.id, channel_type: PERSONAL_CHANNEL_TYPE).select(:id)
  end

  # 非管理员可见的会话范围。
  def scope_for(conversations, user, account)
    conversations.where(inbox_id: personal_inbox_ids(user, account))
                 .or(conversations.where(assignee_id: user.id))
                 .or(conversations.where(id: user.participating_conversations.select(:id)))
  end

  # 单条会话可见性（与 scope_for 同口径，policy 用）。
  def visible?(conversation, user, account)
    return true if conversation.assignee_id == user.id
    return true if conversation.conversation_participants.exists?(user_id: user.id)

    personal_inbox?(conversation.inbox, user, account)
  end

  def personal_inbox?(inbox, user, account)
    return false unless inbox&.channel_type == PERSONAL_CHANNEL_TYPE

    inbox.inbox_members.exists?(user_id: user.id) && inbox.account_id == account&.id
  end

  # 实时推送对象＝**看得见这条会话的人**。管理员由 ActionCableListener#user_tokens 另行补上，
  # 这里不重复查。
  #
  # 公共号只推被指派人与参与者——未分配的会话因此只推给管理员，
  # 跟「业务员看不到未分配」的口径一致。
  # 个人号**在此之外**再加整箱成员（号主）：⚠️ 不能只推号主——号主把某条转给同事协办后，
  # 同事看得见这条会话却收不到新消息推送，得靠手动刷新才知道客户回了。
  def audience(conversation)
    ids = audience_ids(conversation)
    inbox = conversation.inbox
    ids |= inbox.inbox_members.pluck(:user_id) if inbox&.channel_type == PERSONAL_CHANNEL_TYPE
    User.where(id: ids)
  end

  def audience_ids(conversation)
    ids = conversation.conversation_participants.pluck(:user_id)
    ids << conversation.assignee_id
    ids.compact.uniq
  end
end
