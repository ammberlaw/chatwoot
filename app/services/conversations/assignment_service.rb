class Conversations::AssignmentService
  def initialize(conversation:, assignee_id:, assignee_type: nil)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
  end

  def perform
    agent_bot_assignment? ? assign_agent_bot : assign_agent
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type

  def assign_agent
    conversation.assignee = assignee
    conversation.assignee_agent_bot = nil
    reset_seen_for_new_assignee
    conversation.save!
    claim_unowned_customer
    assignee
  end

  # 派活给别人时把会话重新标成未读。
  #
  # 未读是按会话记的(agent_last_seen_at),不是按人记的:老板在自己收件箱里先读过,
  # 转手派给业务员时对方那边一个红点都没有,会话直接沉进列表——实际踩过这个坑,
  # 业务员的反馈是「什么都没发生」。对新接手的人来说他确实一条都没看过,
  # 清空 last_seen 才是如实的。
  #
  # 放在 save 之前:这样指派事件推送出去的数据本身就带未读,不用等刷新。
  # 自己领自己的活不重置——没必要给自己标未读。
  def reset_seen_for_new_assignee
    return if assignee.blank?
    return if Current.user.present? && Current.user.id == assignee.id

    conversation.agent_last_seen_at = nil
    conversation.assignee_last_seen_at = nil
  end

  # 分配会话 ≠ 分配客户。业务员日常看的「我的客户」按 crm_customers.account_owner_id 筛
  # （见 Crm::ConversationViews#customers_for），不看 assignee_id。只派活不改归属，
  # 业务员在「我的客户」里找不到人，体感就是「分了但没收到」——这是实际踩过的坑。
  #
  # 只接管**无主**客户。已经归属同事的一律不动：悄悄划走别人的客户是撞单纠纷的源头，
  # 要转归属得走 reassign 那条有记录的路。公海客户也不在这儿接管——公海有冷却和行锁
  # 规则（见 CustomersController#claim），绕过去会把并发抢单的防护也绕掉。
  def claim_unowned_customer
    return if assignee.blank?

    customer_id = conversation.contact&.crm_customer_id
    return if customer_id.blank?

    customer = conversation.account.crm_customers.find_by(id: customer_id)
    return if customer.blank?
    return if customer.account_owner_id.present? || customer.is_in_public_pool?

    customer.update(account_owner_id: assignee.id)
  end

  def assign_agent_bot
    return unless agent_bot

    conversation.assignee = nil
    conversation.assignee_agent_bot = agent_bot
    conversation.save!
    agent_bot
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  def agent_bot
    @agent_bot ||= AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end
end
