# 客户超期自动进公海（对应 A-CRM recycle-stale-customers 云函数，CRM_SPEC §12.4）。
# 每账户读取公海规则设置：设了专属天数的客户分组按各自天数回收，
# 其余分组（含未分组）按全局 stale_days；可选含从未跟进的客户。
# 每个分组一条批量 UPDATE，避免 N+1。
class Crm::RecycleStaleCustomersJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where(id: Crm::Customer.distinct.select(:account_id)).find_each do |account|
      recycle_for_account(account)
    end
  end

  private

  def recycle_for_account(account)
    settings = Crm::PublicPoolSetting.for_account(account)
    return unless settings.recycle_enabled?

    scope = account.crm_customers.where(is_in_public_pool: false).where.not(account_owner_id: nil)
    per_group = settings.group_recycle_days

    default_scope = scope.where(customer_group: nil).or(scope.where.not(customer_group: per_group.keys))
    count = recycle(default_scope, settings.stale_days.days.ago, settings)
    per_group.each do |group, days|
      count += recycle(scope.where(customer_group: group), days.days.ago, settings)
    end
    Rails.logger.info "[Crm::RecycleStaleCustomersJob] account=#{account.id} recycled=#{count}"
  end

  def recycle(scope, cutoff, settings)
    stale = scope.where('last_follow_up_at <= ?', cutoff)
    stale = stale.or(scope.where('last_follow_up_at IS NULL AND created_at <= ?', cutoff)) if settings.recycle_never_followed?
    # 批量置入公海，单条 UPDATE 无需逐条校验
    stale.update_all(is_in_public_pool: true, public_pool_at: Time.current, account_owner_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
