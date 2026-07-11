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

  # 权重与 Twenty 触发器逐项一致，总分 100。
  def compute_completeness
    s = 0
    s += 5 if trade_country.present?
    s += 5 if website.present?
    s += 4 if industry.present?
    s += 4 if trade_region.present? || trade_city.present?
    s += 7 if primary_contact_name.present?
    s += 16 if contact_email.present?
    s += 10 if whats_app.present? || wechat.present?
    s += 5 if contact_phone.present?
    s += 7 if customer_level.present?
    s += 7 if product_group.present?
    s += 4 if source_channel.present?
    s += 4 if customer_group.present?
    s += 6 if customer_status.present?
    s += 7 if last_follow_up_at.present?
    s += 5 if customer_remark.present?
    s += 4 if risk_level.present?
    self.info_completeness_score = s
    self.completeness_grade = GRADE_FLOORS.find { |_g, floor| s >= floor }&.first || 'POOR'
  end

  def pool_limit_check_needed?
    account_owner_id.present? && customer_group.present? &&
      (will_save_change_to_account_owner_id? || will_save_change_to_customer_group?)
  end

  # 超限拦截：该负责人名下同分组客户数（不含自己）达到上限则拒绝认领/转移。存量不受影响。
  def pool_limit_not_exceeded
    limit = Crm::PublicPoolSetting.for_account(account).limit_for_group(customer_group)
    return if limit.nil? || limit <= 0

    held = account.crm_customers.where(account_owner_id: account_owner_id, customer_group: customer_group)
                  .where.not(id: id).count
    return if held < limit

    errors.add(:account_owner_id, "该分组私海已满（上限 #{limit}）")
  end
end
