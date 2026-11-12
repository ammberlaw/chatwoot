# 离职交接：员工档案被置为「离职」或成员管理页「停用」时触发（需已关联系统账号）。
# 1) 名下客户/商机退回公海，或转移给指定接手人；
# 2) 个人文档进文档回收站（超级管理员可恢复/清理）；
# 3) 该账号停用：CRM 角色置无、禁止登录、踢下线（超级管理员账号不动）。可在成员管理页「恢复」。
class Crm::OffboardingService
  class Invalid < StandardError; end

  def initialize(account:, user_id:, actor:, mode: 'pool', target_user_id: nil, employee: nil, employee_attributes: {})
    @account, @user_id, @actor = account, user_id.to_i, actor
    @mode = mode.presence || 'pool'
    @target_user_id = target_user_id.presence&.to_i
    @employee = employee || @account.crm_employees.find_by(user_id: @user_id)
    @employee_attributes = employee_attributes.to_h.symbolize_keys
  end

  def preview
    validate!
    { customers: @account.crm_customers.where(account_owner_id: @user_id).count,
      opportunities: @account.crm_opportunities.where(owner_id: @user_id).count,
      personal_documents: @account.crm_knowledge_docs.kept.where(scope: 'PERSONAL', owner_id: @user_id).count,
      departments: @account.org_memberships.where(user_id: @user_id).count,
      led_departments: @account.org_departments.where(leader_id: @user_id).count }
  end

  def perform
    validate!
    run = Crm::OffboardingRun.create!(account: @account, employee: @employee, actor: @actor,
                                    user_id: @user_id, mode: @mode, target_user_id: @target_user_id,
                                    summary: { employee_name: @employee&.name || @member.user.crm_display_name })
    @account.with_lock(requires_new: true) do
      @member = @account.account_users.find_by!(user_id: @user_id)
      @employee&.lock!
      validate!
      if @employee_attributes.key?(:user_id) && @employee_attributes[:user_id].to_i != @user_id
        raise Invalid, '办理离职时不能更换关联账号'
      end
      summary = preview.merge(employee_name: @employee&.name || @member.user.crm_display_name)
      handover_customers
      handover_opportunities
      discard_personal_docs
      deactivate_account
      @account.crm_employee_comps.current.where(owner_id: @user_id).update_all(active: false)
      @account.org_departments.where(leader_id: @user_id).find_each { |department| department.update!(leader_id: nil) }
      @account.org_memberships.where(user_id: @user_id).find_each do |membership|
        membership.skip_employee_sync = true
        membership.destroy!
      end
      if @employee
        @employee.update!(@employee_attributes.merge(status: 'RESIGNED'))
        Crm::HrEvent.record!(account: @account, employee: @employee, actor: @actor, kind: 'offboarding_completed', payload: summary)
      end
      run.update!(status: 'completed', summary: summary, completed_at: Time.current)
    end
    leave_company_groups
    run
  rescue StandardError => error
    run&.update!(status: 'failed', error_message: error.is_a?(Invalid) ? error.message : '交接未完成，变更已回滚，可重新办理')
    raise if error.is_a?(Invalid) || error.is_a?(ActiveRecord::RecordInvalid) || error.is_a?(Pundit::NotAuthorizedError)

    Rails.logger.error("[HR交接] #{error.class}: #{error.message}")
    raise Invalid, '交接未完成，变更已回滚，请重新办理'
  end

  private

  def validate!
    actor = @account.account_users.active_members.find_by(user_id: @actor&.id)
    raise Pundit::NotAuthorizedError unless actor && (actor.administrator? || actor.crm_deputy_admin?)
    raise Invalid, '不能停用自己' if @user_id == @actor.id
    @member = @account.account_users.find_by(user_id: @user_id)
    raise Invalid, '离职账号不属于当前公司' unless @member
    raise Invalid, '不能停用超级管理员或管理员账号' if @member.administrator? || @member.crm_deputy_admin?
    raise Invalid, '请选择退回公海或转交' unless %w[pool transfer].include?(@mode)
    if @mode == 'transfer'
      target = @account.account_users.active_members.find_by(user_id: @target_user_id)
      raise Invalid, '接手人必须为本公司其他在职成员' unless target && target.user_id != @user_id
    end
  end

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

  # 停用账号：置无 CRM 角色 + 标记停用（禁止登录）+ 清空令牌踢下线。超级管理员不动。
  def deactivate_account
    au = @account.account_users.find_by(user_id: @user_id)
    return if au.nil? || au.administrator?

    au.update!(crm_role: nil, deactivated_at: au.deactivated_at || Time.current, org_managed_crm_role: false, org_previous_crm_role: nil)
    # A user can belong to other companies. Account-level deactivation blocks this company;
    # only clear global login tokens when there is no other active membership.
    au.user.update_columns(tokens: {}) unless au.user.account_users.active_members.where.not(account_id: @account.id).exists?
  end

  # 离职即退出公司总群（手工建的项目群不动，历史消息也照常保留）。
  def leave_company_groups
    Chat::CompanyGroupSync.on_leave(@account, @user_id)
  rescue StandardError => e
    Rails.logger.warn("[公司总群] 离职成员 #{@user_id} 退群失败：#{e.class} #{e.message}")
  end
end
