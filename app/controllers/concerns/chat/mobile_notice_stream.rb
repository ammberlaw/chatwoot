# App 将 OA/销售订单提醒统一交给工作台待办；Web 保留原有会话历史。
module Chat::MobileNoticeStream
  extend ActiveSupport::Concern

  included do
    helper_method :mobile_notice_view?, :chat_visible_messages, :chat_visible_unread_count
  end

  def mobile_notice_view?
    params[:notice_view] == 'todo_separate'
  end

  def chat_visible_messages(conversation)
    scope = conversation.messages
    return scope unless mobile_notice_view? && conversation.kind != 'group'

    system_id = Crm::SystemUser.existing_id_for(Current.account.id)
    return scope unless system_id && conversation.peer_participant(current_user.id)&.user_id == system_id

    excluded = scope.where(sender_id: system_id, ref_type: %w[oa_approval sales_order]).select(:id)
    scope.where.not(id: excluded)
  end

  def chat_visible_unread_count(conversation)
    return conversation.unread_count_for(current_user.id) unless mobile_notice_view?

    last_read = conversation.participants.find { |p| p.user_id == current_user.id }&.last_read_message_id || 0
    chat_visible_messages(conversation).where('id > ?', last_read).where.not(sender_id: current_user.id).count
  end
end
