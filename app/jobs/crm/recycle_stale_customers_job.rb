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

    scope = recyclable_scope(account, settings)
    per_group = settings.group_recycle_days

    default_scope = scope.where(customer_group: nil).or(scope.where.not(customer_group: per_group.keys))
    count = recycle(default_scope, settings.stale_days.days.ago, settings)
    per_group.each do |group, days|
      count += recycle(scope.where(customer_group: group), days.days.ago, settings)
    end
    Rails.logger.info "[Crm::RecycleStaleCustomersJob] account=#{account.id} recycled=#{count}"
  end

  # 私海有主客户；豁免名单成员的客户不参与自动回收。
  def recyclable_scope(account, settings)
    scope = account.crm_customers.where(is_in_public_pool: false).where.not(account_owner_id: nil)
    return scope if settings.exempt_user_ids.blank?

    scope.where.not(account_owner_id: settings.exempt_user_ids)
  end

  # 超期判定按「最后互动」：跟进 / 邮件 / 下单 / 会话 / 商机任一有动静都算没沉默。
  # 只认手动跟进的话，天天发邮件、刚下过单的客户也会被收进公海——业务不可能接受。
  def recycle(scope, cutoff, settings)
    touch = Crm::Customer::LAST_TOUCH_SQL
    stale = scope.where("#{touch} <= ?", cutoff)
    stale = stale.where.not(last_follow_up_at: nil) unless settings.recycle_never_followed?
    # 批量置入公海（记录原归属人供领回冷却校验），单条 UPDATE 无需逐条校验
    stale.update_all( # rubocop:disable Rails/SkipsModelValidations
      'is_in_public_pool = TRUE, public_pool_at = NOW(), previous_owner_id = account_owner_id, account_owner_id = NULL'
    )
  end
end
