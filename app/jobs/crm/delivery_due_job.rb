# 交期提醒：快到交期、已经逾期的在途订单，每天早上推给负责人。
#
# 为什么现在才能做：交期以前根本不在系统里——122 张在途订单有 102 张（84%）
# 查不到交期，因为它一直以自由文本躺在 PI 条款里（「Delivery time: 30 working
# days after receiving the payment」）。Crm::DeliveryTerm 把那句话解析出来、
# 转单时写进订单之后，这件事才算得出来。
#
# 和 WhatsApp 待回复同一个形态：每天一条汇总，没有就不发。
# 交期不是「晚了两小时」的事，是「这单忘了」的事——忘掉的东西只有列成清单才找得回来。
class Crm::DeliveryDueJob < ApplicationJob
  queue_as :scheduled_jobs

  PREFIX = '【交期提醒】'.freeze
  # 提前这么多天开始提醒。外贸备货、订舱都要时间，到期当天才说已经来不及。
  LOOKAHEAD = 7.days
  MAX_LISTED = 8

  # 货还没到客户手上的阶段。已出货/已完结/已取消的不提醒。
  OPEN_STATUSES = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT].freeze

  def perform
    Account.where(id: Crm::SalesOrder.distinct.select(:account_id)).find_each do |account|
      remind_account(account)
    end
  end

  private

  def remind_account(account)
    sender = Crm::SystemUser.for(account)
    notifier = Chat::NotifyService.new(account: account, sender: sender)

    due_orders(account).group_by(&:owner_id).each do |owner_id, orders|
      next if owner_id.blank? || sent_today?(account, sender.id, owner_id)

      notifier.notify(owner_id, compose(orders), ref: ref_for(orders.first))
    end
  end

  # 已逾期的排前面，其次按交期由近到远。
  def due_orders(account)
    account.crm_sales_orders
           .where(status: OPEN_STATUSES)
           .where(delivery_date: ..LOOKAHEAD.from_now)
           .where.not(delivery_date: nil)
           .order(:delivery_date, :id)
  end

  def compose(orders)
    overdue = orders.count { |o| o.delivery_date.to_date < Date.current }
    listed = orders.first(MAX_LISTED).map { |o| line(o) }
    more = orders.size - listed.size
    [
      "#{PREFIX}#{orders.size} 单",
      overdue.positive? ? "其中 #{overdue} 单已经过了交期。" : '下面这些快到交期了。',
      '',
      *listed,
      (more.positive? ? "（另有 #{more} 单，去销售订单列表按交期排）" : nil)
    ].compact.join("\n")
  end

  def line(order)
    days = (order.delivery_date.to_date - Date.current).to_i
    when_text =
      if days.negative?
        "已逾期 #{-days} 天"
      elsif days.zero?
        '今天到期'
      else
        "还有 #{days} 天"
      end
    "· #{order.order_no}｜#{order.crm_customer&.name.to_s.truncate(16)}｜" \
      "#{Crm::SalesOrder::STATUS_LABELS[order.status]}｜#{when_text}"
  end

  def ref_for(order)
    { type: 'sales_order', id: order.id, label: '销售订单',
      title: order.order_no.to_s, subtitle: order.crm_customer&.name.to_s }
  end

  # 一人一天最多一条（口径同 Crm::WhatsappUnansweredJob）。
  def sent_today?(account, sender_id, user_id)
    conversation_ids = account.chat_conversations.where(kind: 'direct')
                              .joins(:participants)
                              .where(chat_participants: { user_id: user_id }).select(:id)
    Chat::Message.where(conversation_id: conversation_ids, sender_id: sender_id)
                 .where('content LIKE ?', "#{PREFIX}%")
                 .exists?(created_at: Time.zone.today.all_day)
  end
end
