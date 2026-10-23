class Chat::MobilePushJob < ApplicationJob
  queue_as :default
  retry_on Notification::NativePushService::DeliveryError, wait: :polynomially_longer, attempts: 5

  # 「系统通知」挂着单据发出的提醒走独立 kind，点推送直接落到那张单、当场能办，
  # 而不是落进聊天只看到一行字。
  #
  # 每类单据两种形态共用一个 kind（App 白名单固定，后端加不了新 kind），锁屏文案分开：
  # 轮到你办（pending_marker 命中快照里的状态后缀）vs 你的单有了结果。办完了还弹
  # 「等你审核」，点开发现没事可做。
  REF_PUSH = {
    'sales_order' => { kind: 'sales_order_approval', pending_marker: '待审核',
                       result_alert: 'sales_order_result' },
    'oa_approval' => { kind: 'approval', pending_marker: '待审批',
                       result_alert: 'approval_result' }
  }.freeze

  def perform(message_id)
    message = Chat::Message.find_by(id: message_id)
    return unless message

    kind, entity_id, alert_kind = push_target(message)
    return if kind.nil?

    NotificationSubscription.native.where(user_id: unread_member_ids(message)).find_each do |subscription|
      next unless subscription.subscription_attributes['account_id'].to_i == message.account_id
      next if stale_for?(message, subscription.user_id)

      Notification::NativePushService.new.deliver(
        subscription: subscription, account_id: message.account_id, user_id: subscription.user_id,
        kind: kind, conversation_id: message.conversation_id, entity_id: entity_id, message_id: message.id,
        alert_kind: alert_kind
      )
    end
  end

  private

  # Membership and read state are checked when the job runs, after the message commit.
  def unread_member_ids(message)
    members = message.conversation.participants.where.not(user_id: message.sender_id)
                     .where('COALESCE(last_read_message_id, 0) < ?', message.id)
                     .pluck(:user_id)
    AccountUser.where(account_id: message.account_id, user_id: members, deactivated_at: nil).pluck(:user_id)
  end

  # 只认系统通知这一个发送人：同事在团队沟通里手动引用一张订单说「这单你看下」，
  # 那是会话消息，点开必须进聊天看他说了什么，不能跳走。
  def push_target(message)
    return ['team', nil] if message.ref_id.blank?
    return ['team', nil] unless message.sender_id == Crm::SystemUser.existing_id_for(message.account_id)
    # 新询盘初筛挂的也是 email ref，但新邮件本身已由 Crm::MailPushJob 推过一条了
    # （kind='mail'），这里再推一条就是同一封信响两次。初筛那 600 字 AI 分析
    # 本来就该在 Web 上细看，不适合塞进锁屏。
    return nil if message.ref_type == 'email'

    meta = REF_PUSH[message.ref_type]
    return ['team', nil] if meta.nil?

    [meta[:kind], message.ref_id, pending_reminder?(message) ? meta[:kind] : meta[:result_alert]]
  end

  # 这条提醒是「轮到你办」还是「你的单有了结果」。靠通知卡片快照里的状态后缀分辨
  # （sales_orders_controller 写「业务员 · 待审核/已审核/已驳回」、
  #  Oa::ApprovalNotifier 写「申请人 · 待审批/已通过/已驳回/已撤回」）。
  def pending_reminder?(message)
    meta = REF_PUSH[message.ref_type]
    meta.present? && message.ref_snapshot.to_h['subtitle'].to_s.include?(meta[:pending_marker])
  end

  # 发之前按**当下**的单据状态和审批权限复核一遍：DeliveryError 退避重试最多跨好几分钟，
  # 这期间单子很可能已经流转走了，再推就是催一个早批完的人、或催一个已经没权限审的人。
  # 结果类通知是既成事实，不会过期，不参与这道复核。
  def stale_for?(message, user_id)
    return false unless pending_reminder?(message)

    case message.ref_type
    when 'sales_order' then stale_sales_order?(message, user_id)
    when 'oa_approval' then stale_oa_approval?(message, user_id)
    else false
    end
  end

  def stale_sales_order?(message, user_id)
    order = Crm::SalesOrder.find_by(id: message.ref_id, account_id: message.account_id)
    return true if order.nil? || order.approval_status != 'PENDING'

    # 与控制器挡写、jbuilder 显按钮同一口径，不另写一份。
    account_user = AccountUser.find_by(account_id: message.account_id, user_id: user_id)
    !Crm::SalesOrderApprover.can?(account_user, order)
  end

  def stale_oa_approval?(message, user_id)
    request = Oa::ApprovalRequest.find_by(id: message.ref_id, account_id: message.account_id)
    return true if request.nil? || !request.pending?

    # 节点已经往下走了（或整单已终结）→ 这个人不再是当前审批人，别催他。
    request.current_step&.approver_id != user_id
  end
end
