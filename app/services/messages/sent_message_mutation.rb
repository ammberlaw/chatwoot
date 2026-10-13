# 「动一条已经发到客户手机上的消息」——撤回和编辑的公共部分。
#
# 两件事的规矩是同一套，分开写早晚会走偏：
#   · 只有发这条的人能动（管理员也不能代劳，谁发的谁负责）
#   · 只能动真的发出去了的（没有 source_id 就无从谈起）
#   · 撤回过的不能再动
#   · WhatsApp 自己的时间窗要先卡住——超窗发过去对方客户端不认、也不报错，
#     界面上却会显示成功，那是最糟的结果
#
# 先发后记：外发失败就不动本地那条，免得 CRM 显示「已撤回」而客户手机上原文还在。
class Messages::SentMessageMutation
  class Error < StandardError; end
  class UnsupportedChannel < Error; end

  def perform
    validate!
    deliver
    record
  end

  private

  def channel
    @channel ||= message.inbox.channel
  end

  # 客户那头的地址。会话的 source_id 可能是手机号也可能是 LID，原样交给桥。
  def recipient
    message.conversation.contact_inbox.source_id
  end

  def validate!
    raise UnsupportedChannel, unsupported_reason if unsupported_reason.present?
    raise Error, "只能#{action_name}自己发出的消息" unless own_outgoing?
    raise Error, '这条消息还没真正发出去' if message.source_id.blank?
    raise Error, '这条消息已经撤回了' if message.content_attributes['revoked']
    raise Error, expiry_error if expired?

    extra_validate!
  end

  # 官方号（Meta Cloud API）根本没给这两个接口，别让人点完以为成功了。
  def unsupported_reason
    case message.inbox.channel_type
    when 'Channel::WhatsappWeb' then nil
    when 'Channel::Whatsapp' then "WhatsApp 官方号不支持#{action_name}，只能在本系统里删除"
    else "#{channel.name} 不支持#{action_name}"
    end
  end

  def own_outgoing?
    message.outgoing? && message.sender_type == 'User' && message.sender_id == user.id
  end

  def expired?
    message.created_at < self.class::WINDOW.ago
  end

  # 子类各自补自己的额外校验；默认没有。
  def extra_validate!; end
end
