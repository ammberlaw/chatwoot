# agent 取数的权限收口。
#
# agent 跑在后台任务里，拿不到控制器那套 Current/helper，所以这里按同一套口径重算一遍。
# ⚠️ 口径必须和 Api::V1::Accounts::Crm::BaseController 的 visible_customers /
# scope_by_mail_owner / scope_by_team_owner 保持一致——两边一走偏，就等于开了一个
# 「用 AI 能看到别人客户和别人邮件」的后门。
class Crm::Agent::Scope
  def initialize(account:, account_user:)
    @account = account
    @account_user = account_user
    @access = Crm::AccessScope.new(account, account_user)
  end

  attr_reader :account

  def user_id = @account_user&.user_id

  # 可见私海（团队口径归属 + 被共享）∪ 公海
  def customers
    ids = @access.team_visible_owner_ids
    return @account.crm_customers if ids == :all

    @account.crm_customers.where(
      'crm_customers.account_owner_id IN (:ids) OR :uid = ANY(crm_customers.shared_user_ids) ' \
      'OR crm_customers.is_in_public_pool',
      ids: ids, uid: user_id
    )
  end

  # 邮件是私人往来：老板看全员，CRM 团队负责人看本团队，其余只看自己。
  def emails
    ids = @access.mail_visible_owner_ids
    ids == :all ? @account.crm_emails : @account.crm_emails.where(owner_id: ids)
  end

  def sales_orders
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_sales_orders : @account.crm_sales_orders.where(owner_id: ids)
  end

  def pis
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_pis : @account.crm_pis.where(owner_id: ids)
  end

  def opportunities
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_opportunities : @account.crm_opportunities.where(owner_id: ids)
  end

  # 跟进任务的负责人列是 assignee_id（与跟进任务列表控制器同口径）。
  def follow_up_tasks
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_follow_up_tasks : @account.crm_follow_up_tasks.where(assignee_id: ids)
  end

  # 应收自己那个 owner_id 可能是空的（财务手工建的单），所以跟着**客户**的可见范围走，
  # 不按 owner_id——否则业务员问「谁还欠钱」会漏掉一批本该他管的客户。
  def receivables
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.erp_receivables : @account.erp_receivables.where(crm_customer_id: customers.select(:id))
  end
end
