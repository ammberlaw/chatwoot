# 客户三个「系统计算」行为，移植自 Twenty DB 触发器（CRM_SPEC §12.5）：
# ① 客户编号自动生成（customer-code-autonumber：WT+7 位，按账户递增，删除不回填）
# ② 资料完善度评分+等级（customer-completeness-score：16 项加权总分 100）
# ③ 私海上限守卫（customer-pool-limit：认领/转移时按 负责人×客户分组 计数拦截）
module Crm::CustomerScoring
  extend ActiveSupport::Concern

  GRADE_FLOORS = { 'COMPLETE' => 85, 'GOOD' => 60, 'FAIR' => 40 }.freeze

  included do
    before_create :assign_customer_code
    before_save :compute_completeness
    validate :pool_limit_not_exceeded, if: :pool_limit_check_needed?
  end

  private

  def assign_customer_code
    return if customer_code.present?

    last = account.crm_customers
                  .where("customer_code ~ '^WT[0-9]+$'")
                  .pick(Arel.sql("MAX(SUBSTRING(customer_code FROM 3)::int)")) || 0
    self.customer_code = format('WT%07d', last + 1)
  end

  # 14 项加权，总分 100。两次调整都只动权重、不动总分，等级门槛（GRADE_FLOORS）才一直可比：
  # ① 原有「风险等级 4 分」取消计分（字段保留、仍可填），那 4 分并入过「最近跟进」；
  # ② 2026-10-31「最近跟进 11 分」也取消：当初的前提是它由系统自动写入，
  #    实际上只有人手点了跟进按钮才会有值（生产 13231 个客户里只有 145 个有），
  #    等于全员白丢 11 分、等级被整体压低。而且这是**资料**完整度，
  #    跟没跟进属于活跃度，本来就不该混在一起（活跃度看 LAST_TOUCH_SQL）。
  #    这 11 分按「对外贸有多关键」分回最核心的几项资料。
  def compute_completeness
    s = 0
    s += 8 if trade_country.present?
    s += 5 if website.present?
    s += 4 if industry.present?
    s += 4 if trade_region.present? || trade_city.present?
    s += 9 if primary_contact_name.present?
    s += 20 if contact_email.present?
    s += 10 if whats_app.present? || wechat.present?
    s += 5 if contact_phone.present?
    s += 7 if customer_level.present?
    s += 8 if product_group.present?
    s += 4 if source_channel.present?
    s += 4 if customer_group.present?
    s += 7 if customer_status.present?
    s += 5 if customer_remark.present?
    self.info_completeness_score = s
    self.completeness_grade = GRADE_FLOORS.find { |_g, floor| s >= floor }&.first || 'POOR'
  end

  def pool_limit_check_needed?
    account_owner_id.present? && customer_group.present? &&
      (will_save_change_to_account_owner_id? || will_save_change_to_customer_group?)
  end

  # 超限拦截：该负责人名下同分组客户数（不含自己）达到上限则拒绝认领/转移。存量不受影响。
  # 豁免名单成员不受上限约束（与回收豁免同一名单）。
  def pool_limit_not_exceeded
    settings = Crm::PublicPoolSetting.for_account(account)
    return if settings.exempt_user_ids.include?(account_owner_id)

    limit = settings.limit_for_group(customer_group)
    return if limit.nil? || limit <= 0

    held = account.crm_customers.where(account_owner_id: account_owner_id, customer_group: customer_group)
                  .where.not(id: id).count
    return if held < limit

    errors.add(:account_owner_id, "该分组私海已满（上限 #{limit}）")
  end
end
