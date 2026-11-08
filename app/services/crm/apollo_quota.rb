# Apollo 积分额度：按人按月分配，用完就不让解锁了。
#
# 为什么只管「解锁联系方式」：Apollo 的两段式设计里，搜公司（mixed_companies/search）
# 和搜联系人预览（mixed_people/api_search）都**不扣积分**，只有 people/match 要真金白银。
# 所以额度卡在这一步，既管住了花销，又不影响业务员翻名单、看背调。
#
# ⚠️ Apollo 没有查余额的接口（usage_stats 返回 404，2026-11-08 实测），
# 所以用量只能我们自己记——解锁时往线索上写 unlocked_by_id / unlocked_at，
# 这张账也顺便回答了「积分花在哪了」。
class Crm::ApolloQuota
  Status = Struct.new(:user_limit, :user_used, :account_limit, :account_used, keyword_init: true) do
    # 没设上限就是不限，剩余按 nil 表示「不限」，别拿 0 当不限。
    def user_left = user_limit && [user_limit - user_used, 0].max
    def account_left = account_limit && [account_limit - account_used, 0].max
    def allowed? = (user_left.nil? || user_left.positive?) && (account_left.nil? || account_left.positive?)

    # 拦下来的时候要说清是谁的额度到顶了，不然业务员只会看到「不让解锁」。
    def block_reason
      return nil if allowed?
      return '本月全公司的 Apollo 解锁额度已用完' if account_left&.zero?

      '你本月的 Apollo 解锁额度已用完'
    end
  end

  def initialize(account:)
    @account = account
    @setting = Crm::AiSetting.for_account(account)
  end

  def status_for(user)
    Status.new(user_limit: limit_for(user), user_used: used(user_id: user&.id),
               account_limit: @setting.apollo_monthly_limit, account_used: used)
  end

  def allow?(user) = status_for(user).allowed?

  # 个别人单独配了就用他的，否则用统一的默认值。
  def limit_for(user)
    return nil if user.nil?

    override = @setting.apollo_user_limits.to_h[user.id.to_s]
    override.presence&.to_i || @setting.apollo_user_limit
  end

  # 本月解了多少条。按自然月算——额度是按月给的，跨月自动清零，不做结转。
  def used(user_id: nil)
    scope = @account.crm_leads.where(unlocked_at: Time.current.all_month)
    scope = scope.where(unlocked_by_id: user_id) if user_id
    scope.count
  end

  # 背调查企业库的次数。是否计费 Apollo 没说死，所以只计数不设限，
  # 摆在设置页上让人自己看量（真要控，关掉自动背调即可）。
  def bg_checks_this_month
    @account.crm_leads.where("(raw->'bg'->>'checked_at')::timestamptz >= ?",
                             Time.current.beginning_of_month).count
  end
end
