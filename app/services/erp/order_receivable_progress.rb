# 销售订单的回款进度（ERP_SPEC §2.5）：给 CRM 订单页的只读进度条用。
#
# ⚠️ 透出边界：**只有回款**——应收总额、已收、未收、分期到期情况。
# 成本、应付、毛利、账簿一个字都不给，销售端与成本硬隔离（ERP_SPEC §2.5 / 生态硬约束）。
#
# 分期的「这期还欠多少」走 Erp::InstallmentFifo，与账龄分析、催收预警同一套冲抵口径——
# 业务员在订单页看到的欠款，必须和财务催收提醒里喊的是同一个数。
class Erp::OrderReceivableProgress
  def initialize(sales_order)
    @order = sales_order
  end

  # ERP 没上线（总开关关）或财务还没给这张订单建账 → nil，前端整块不渲染。
  def call
    return nil unless Erp.enabled?

    receivable = find_receivable
    return nil if receivable.blank?

    slots = Erp::InstallmentFifo.settle(receivable)
    summary(receivable).merge(installments: slots.map { |slot| installment_row(slot) },
                              next_due: next_due(slots))
  end

  private

  def find_receivable
    @order.account.erp_receivables.includes(:installments).find_by(crm_sales_order_id: @order.id)
  end

  def summary(receivable)
    {
      receivable_no: receivable.receivable_no,
      currency: receivable.currency,
      status: receivable.derived_status,
      status_label: Erp::Receivable::STATUS_LABELS[receivable.derived_status],
      total_micros: receivable.total_amount_micros,
      received_micros: receivable.received_amount_micros,
      outstanding_micros: receivable.outstanding_micros,
      # 进度条百分比在后端算，前后端两套四舍五入会对不上（已收清却显示 99%）。
      received_percent: percent_of(receivable)
    }
  end

  def percent_of(receivable)
    total = receivable.total_amount_micros.to_i
    return 0 if total <= 0
    return 100 if receivable.outstanding_micros <= 0

    ((receivable.received_amount_micros.to_f / total) * 100).floor.clamp(0, 99)
  end

  def installment_row(slot)
    installment = slot[:installment]
    {
      id: installment&.id,
      seq: installment&.seq,
      kind_label: slot[:note],
      due_basis_label: installment && Erp::ReceivableInstallment::DUE_BASIS_LABELS[installment.due_basis],
      due_date: slot[:due_date],
      amount_micros: slot[:amount_micros],
      received_micros: slot[:settled_micros],
      outstanding_micros: slot[:open_micros],
      status: slot_status(slot),
      days: days_of(slot)
    }
  end

  # 分期状态按 FIFO 冲抵后的真实余额判，不用 installment#derived_status——
  # 后者只看整张台账收没收清，分期收了一半照样显示「未到期」。
  def slot_status(slot)
    return 'SETTLED' if slot[:open_micros] <= 0
    return 'PENDING' if slot[:due_date].blank?

    days = days_of(slot)
    return 'OVERDUE' if days.positive?

    days >= -Erp::ReceivableInstallment::DUE_SOON_DAYS ? 'DUE_SOON' : 'PENDING'
  end

  def days_of(slot)
    return nil if slot[:due_date].blank?

    (Time.zone.today - slot[:due_date]).to_i
  end

  # 下一期到期日 = 最早的、还欠钱的、排了到期日的那一期（FIFO 顺序即是到期顺序）。
  def next_due(slots)
    slot = slots.find { |item| item[:open_micros].positive? && item[:due_date].present? }
    return nil if slot.blank?

    {
      due_date: slot[:due_date], kind_label: slot[:note],
      outstanding_micros: slot[:open_micros], days: days_of(slot)
    }
  end
end
