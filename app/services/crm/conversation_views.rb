# CRM 维度的会话视图：业务员按「谁的客户 / 要不要跟 / 建没建档」分诊会话，
# 而不是从上往下一条条翻。都收敛到 contacts.crm_customer_id 这条关联上。
class Crm::ConversationViews
  TYPES = %w[crm_mine crm_unfiled crm_overdue crm_hot].freeze
  # 按客户来源筛：来源 code 跟在 type 后面（crm_source:EXHIBITION），这样不用再往
  # ChatList / 会话接口里多塞一个参数，沿用现成的 conversation_type 通道。
  SOURCE_PREFIX = 'crm_source:'.freeze
  SOURCE_TYPE = /\Acrm_source:/

  def initialize(account:, user:, scope:)
    @account = account
    @user = user
    @scope = scope
  end

  def apply(type)
    return by_source_tag(type.to_s.delete_prefix(SOURCE_PREFIX)) if type.to_s.start_with?(SOURCE_PREFIX)

    # 还没建档成客户的——新询盘多半在这里
    return by_contacts(@account.contacts.where(crm_customer_id: nil)) if type == 'crm_unfiled'

    customers = customers_for(type)
    by_contacts(@account.contacts.where(crm_customer_id: customers.select(:id)))
  end

  private

  def by_contacts(contacts)
    @scope.where(contact_id: contacts.select(:id))
  end

  # 来源标签打在会话上，存成 additional_attributes.crm_source_tags 的 jsonb 数组（存 code）。
  def by_source_tag(code)
    return @scope.none if code.blank?

    @scope.where("conversations.additional_attributes -> 'crm_source_tags' @> ?::jsonb", [code].to_json)
  end

  def customers_for(type)
    scope = @account.crm_customers
    case type
    when 'crm_mine' then scope.where(account_owner_id: @user.id)
    # 下次跟进已到期/过期的，只看自己名下的
    when 'crm_overdue'
      scope.where(account_owner_id: @user.id)
           .where.not(next_follow_up_at: nil)
           .where(next_follow_up_at: ..Time.current)
    # 高意向：跟进中 + A/B 级
    when 'crm_hot' then scope.where(customer_status: 'FOLLOWING', customer_level: %w[A B])
    else scope
    end
  end
end
