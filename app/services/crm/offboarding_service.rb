# 离职交接：员工档案被置为「离职」时触发（需档案已关联系统账号）。
# 1) 名下客户/商机退回公海，或转移给指定接手人；
# 2) 个人文档进文档回收站（超级管理员可恢复/清理）；
# 3) 该账号 CRM 角色置无（不再能进入 CRM；超级管理员账号不动）。
class Crm::OffboardingService
  def initialize(account:, user_id:, mode: 'pool', target_user_id: nil)
    @account = account
    @user_id = user_id
    @mode = mode == 'transfer' && target_user_id.present? ? 'transfer' : 'pool'
    @target_user_id = target_user_id
  end

  def perform
    handover_customers
    handover_opportunities
    discard_personal_docs
    revoke_crm_role
  end

  private

  def handover_customers
    scope = @account.crm_customers.where(account_owner_id: @user_id)
    if @mode == 'transfer'
      scope.update_all(account_owner_id: @target_user_id) # rubocop:disable Rails/SkipsModelValidations
    else
      scope.update_all(account_owner_id: nil, is_in_public_pool: true, public_pool_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def handover_opportunities
    scope = @account.crm_opportunities.where(owner_id: @user_id)
    if @mode == 'transfer'
      scope.update_all(owner_id: @target_user_id) # rubocop:disable Rails/SkipsModelValidations
    else
      scope.update_all(owner_id: nil, is_in_public_pool: true, public_pool_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def discard_personal_docs
    @account.crm_knowledge_docs.kept.where(scope: 'PERSONAL', owner_id: @user_id).find_each do |doc|
      doc.discard!(@user_id)
    end
  end

  def revoke_crm_role
    au = @account.account_users.find_by(user_id: @user_id)
    return if au.nil? || au.administrator?

    au.update!(crm_role: nil)
  end
end
