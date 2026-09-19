class BaseListener
  include Singleton

  def extract_conversation_and_account(event)
    conversation = event.data[:conversation]
    [conversation, conversation.account]
  end

  def extract_notification_and_account(event)
    notification = event.data[:notification]
    notification_finder = NotificationFinder.new(notification.user, notification.account)
    unread_count = notification_finder.unread_count
    count = notification_finder.count
    [notification, notification.account, unread_count, count]
  end

  def extract_message_and_account(event)
    message = event.data[:message]
    [message, message.account]
  end

  def extract_contact_and_account(event)
    contact = event.data[:contact]
    [contact, contact.account]
  end

  def extract_inbox_and_account(event)
    inbox = event.data[:inbox]
    [inbox, inbox.account]
  end

  # 会话事件该推给谁：**看得见这条会话的人**，不是整个收件箱的成员。
  # 公司公共号十几个成员全是业务员，按收件箱成员推等于把别人客户的消息内容推进每个人的浏览器——
  # 前端不显示不等于没送到。口径与列表过滤、单条鉴权同源（Conversations::Visibility）。
  def conversation_audience(conversation)
    Conversations::Visibility.audience(conversation)
  end

  def extract_changed_attributes(event)
    changed_attributes = event.data[:changed_attributes]

    return if changed_attributes.blank?

    changed_attributes.map { |k, v| { k => { previous_value: v[0], current_value: v[1] } } }
  end
end
