# 客户超期自动进公海（对应 A-CRM recycle-stale-customers 云函数，CRM_SPEC §12.4）。
# 每账户读取公海规则设置：超过 stale_days 未跟进（可选含从未跟进）的在私海客户
# 批量置入公海并清空负责人。单条 UPDATE，避免 N+1。
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

    cutoff = settings.stale_days.days.ago
    scope = account.crm_customers.where(is_in_public_pool: false).where.not(account_owner_id: nil)
    stale = scope.where('last_follow_up_at <= ?', cutoff)
    if settings.recycle_never_followed?
      stale = stale.or(scope.where('last_follow_up_at IS NULL AND created_at <= ?', cutoff))
    end

    count = stale.update_all(is_in_public_pool: true, public_pool_at: Time.current, account_owner_id: nil)
    Rails.logger.info "[Crm::RecycleStaleCustomersJob] account=#{account.id} recycled=#{count} cutoff=#{cutoff}"
  end
end
