# CRM 所有控制器的基类：统一「能否进入 CRM」门禁 + 「按负责人的数据范围」助手。
# 门禁：系统管理员或被赋予 CRM 角色（主管/业务员）者可入；其他部门成员一律 403。
# 数据范围：见 Crm::AccessScope —— 管理员全部 / 主管团队 / 业务员本人。
class Api::V1::Accounts::Crm::BaseController < Api::V1::Accounts::BaseController
  include PaginationParamNormalizer

  before_action :ensure_crm_access

  private

  def ensure_crm_access
    return if Current.account_user&.can_access_crm?

    render json: { error: I18n.t('errors.crm.no_access', default: '无权访问 CRM') }, status: :forbidden
  end

  # 「纯财务」：有 crm_finance 标记、但没有 crm_role，所以过不了 CRM 总门禁。
  # 销售订单与 PI 是财务对账的刚需，单独放行给他们；客户资源/邮件/报价仍然挡着。
  def crm_finance_only?
    au = Current.account_user
    au.present? && au.crm_finance? && !au.can_access_crm?
  end

  # 销售订单/PI 用：CRM 成员照旧，纯财务也放进来。
  def ensure_crm_or_finance!
    return if Current.account_user&.can_access_crm? || crm_finance_only?

    render json: { error: I18n.t('errors.crm.no_access', default: '无权访问 CRM') }, status: :forbidden
  end

  # 财务是只读的。用 except: 列读操作而不是 only: 列写操作——将来新增 action
  # 默认被挡住，而不是默认放行（漏一个就是越权）。
  def block_crm_finance_writes!
    return unless crm_finance_only?

    render json: { error: '财务为只读权限，不能新增或修改' }, status: :forbidden
  end

  # 财务对账要看全公司，按业务员收敛没有意义；其余人照旧按归属收敛。
  def scope_docs_for_finance_or(relation, team: false)
    return relation if crm_finance_only?

    scope_docs_visible(relation, team: team)
  end

  # 团队沟通「系统通知」：CRM 各审批节点自动提醒成员/主管，以「系统通知」名义发单聊。
  # 失败在 NotifyService 内部兜住、只记日志，不阻断主业务流程。
  def crm_notify(target_id, content)
    return if target_id.blank?

    Chat::NotifyService.new(account: Current.account, sender: Crm::SystemUser.for(Current.account))
                       .notify(target_id, content)
  end

  # 提交考核/提成后，通知该成员的直属主管们（可能不止一个部门）去审。
  def crm_notify_managers_of(user_id, content)
    Org::Department.managers_of(Current.account, user_id).each { |mid| crm_notify(mid, content) }
  end

  # 当前成员可见的负责人 id：:all 或 user_id 数组。
  def crm_visible_owner_ids
    @crm_visible_owner_ids ||=
      Crm::AccessScope.new(Current.account, Current.account_user).visible_owner_ids
  end

  # 邮件专用可见负责人 id：:all（仅系统管理员/老板）或 user_id 数组（CRM 团队负责人=本团队；其余=自己）。
  def crm_mail_visible_owner_ids
    @crm_mail_visible_owner_ids ||=
      Crm::AccessScope.new(Current.account, Current.account_user).mail_visible_owner_ids
  end

  # 按邮件口径限定 crm_emails 范围；:all 不加限制。
  def scope_by_mail_owner(relation)
    ids = crm_mail_visible_owner_ids
    ids == :all ? relation : relation.where(owner_id: ids)
  end

  # CRM 团队口径可见负责人 id：:all（管理员/副管理员）或 user_id 数组（团队负责人=本团队；其余=自己）。
  def crm_team_visible_owner_ids
    @crm_team_visible_owner_ids ||=
      Crm::AccessScope.new(Current.account, Current.account_user).team_visible_owner_ids
  end

  # 按 CRM 团队口径限定数据范围（当前用于销售订单）；:all 不加限制。
  def scope_by_team_owner(relation, column: :owner_id)
    ids = crm_team_visible_owner_ids
    ids == :all ? relation : relation.where(column => ids)
  end

  # 客户可见范围：可见私海（团队口径归属 + 被共享）∪ 公海（认领/查看用）；:all 不加限制。
  # 客户及其联系人的按 id 直取都应走此收口，防止越权读改他人私海客户（IDOR）。
  def visible_customers
    ids = crm_team_visible_owner_ids
    return Current.account.crm_customers if ids == :all

    Current.account.crm_customers.where(
      'crm_customers.account_owner_id IN (:ids) OR :uid = ANY(crm_customers.shared_user_ids) OR crm_customers.is_in_public_pool',
      ids: ids, uid: current_user.id
    )
  end

  # 按负责人列限定数据范围；:all 不加限制。默认列 owner_id（客户用 account_owner_id）。
  def scope_by_owner(relation, column: :owner_id)
    ids = crm_visible_owner_ids
    ids == :all ? relation : relation.where(column => ids)
  end

  # 单据业绩归属人：PI/销售订单/报价的业绩计入「客户归属人」而非创建人。
  # 共享客户里被共享的助理建单，业绩仍归客户归属人（老板）；公海/未分配客户回落到创建人。
  def performance_owner_id(crm_customer_id)
    return current_user.id if crm_customer_id.blank?

    owner = Current.account.crm_customers.where(id: crm_customer_id).pick(:account_owner_id)
    owner || current_user.id
  end

  # 单据(PI/销售订单/报价)可见范围：按负责人授权 + 额外放行「我经办的」。
  # 经办人(共享客户里实际建单的助理)在自己账号也能看到这些单（业绩仍归老板）。
  def scope_docs_visible(relation, team: false)
    ids = team ? crm_team_visible_owner_ids : crm_visible_owner_ids
    return relation if ids == :all

    relation.where('owner_id IN (:ids) OR handled_by_id = :uid', ids: ids, uid: current_user.id)
  end

  # 「我的」单据 = 我负责的(业绩归我) + 我经办的(共享客户里我建的)。
  def scope_docs_mine(relation)
    relation.where('owner_id = :uid OR handled_by_id = :uid', uid: current_user.id)
  end
end
