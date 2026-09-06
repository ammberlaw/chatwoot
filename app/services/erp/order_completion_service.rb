# 销售订单自动完结：已出货 + 应收已收清 → COMPLETED。
#
# 为什么要两个触发点：这门生意两种付款节奏都有——
#   先货后款：出货(SHIPPED) → 收款核销收清 → 完结   （由核销侧触发）
#   先款后货：PI 付款转订单就已收清 → 出货 → 完结   （由出货侧触发）
# 少接哪一头，对应那类订单就永远停在 SHIPPED。
#
# 只在 SHIPPED ⇄ COMPLETED 之间切换，绝不碰 CANCELLED 或未出货的订单——
# 业务状态是 CRM 的，ERP 只负责"钱收清了没"这一个判据。
class Erp::OrderCompletionService
  SHIPPED = 'SHIPPED'.freeze
  COMPLETED = 'COMPLETED'.freeze

  def initialize(account)
    @account = account
  end

  # 按销售订单判。返回是否发生了状态变更。
  def sync!(sales_order)
    return false if sales_order.blank?
    return false unless [SHIPPED, COMPLETED].include?(sales_order.status)

    settled = fully_received?(sales_order)
    target = settled ? COMPLETED : SHIPPED
    return false if sales_order.status == target

    # 只动 status 一列：走 update! 会连带触发订单的汇率重取/团队反写等回调，
    # ERP 判个收清不该顺手改业务字段。与 MES 出货回写 SHIPPED 的写法一致。
    sales_order.update_columns(status: target, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    true
  end

  # 从应收台账那头触发（核销/作废后调用）。
  def sync_for_receivable(receivable)
    sync!(receivable.crm_sales_order)
  end

  private

  # 没建应收台账的订单不算"收清"——没建账等于财务还没确认这笔钱，
  # 直接判完结会把漏建账的单子悄悄标成已完结，反而盖住问题。
  def fully_received?(sales_order)
    ledgers = @account.erp_receivables.where(crm_sales_order_id: sales_order.id)
    return false if ledgers.empty?

    ledgers.all? { |ledger| ledger.outstanding_micros <= 0 }
  end
end
