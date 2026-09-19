# 已收款按到期日 FIFO 冲抵分期——「先到期的先冲」，剩下没冲掉的才是这一期真欠的钱。
#
# ⚠️ 为什么非共用不可：账龄分析（AgingService）、催收预警（AlertScannerService）、
# 订单回款进度（CRM 订单页）三处都要回答「这一期还欠多少」。各写一套迟早算出三个数，
# 财务对账时谁也说服不了谁；更糟的是「30% 订金 + 70% 尾款」的单子——订金早收了、
# 尾款还没到期，不按到期日冲抵就会把整笔订金报成逾期天天喊。
class Erp::InstallmentFifo
  # 分期金额之和小于台账总额时，差额挂一条无到期日的「未排期」槽——
  # 不挂的话这笔钱在账龄和进度条里凭空消失，台账总额就对不上分期之和。
  UNSCHEDULED_NOTE = '未排期'.freeze

  # 返回按 FIFO 顺序排好的槽：
  #   { installment:（未排期槽为 nil）, due_date:, kind:, note:, amount_micros:, settled_micros:, open_micros: }
  def self.settle(receivable)
    new(receivable).settle
  end

  # FIFO 顺序：先到期的先冲，没排到期日的排最后（同日按 seq）。
  def self.order_key(installment)
    [installment.due_date ? 0 : 1, installment.due_date || Date.new(9999), installment.seq.to_i]
  end

  def initialize(receivable)
    @receivable = receivable
  end

  def settle
    left = @receivable.received_amount_micros.to_i
    slots.map do |slot|
      settled = [left, slot[:amount_micros]].min
      left -= settled
      slot.merge(settled_micros: settled, open_micros: slot[:amount_micros] - settled)
    end
  end

  private

  def slots
    rows = @receivable.installments.sort_by { |item| self.class.order_key(item) }.map { |item| slot_of(item) }
    rest = @receivable.total_amount_micros.to_i - rows.sum { |slot| slot[:amount_micros] }
    rows << unscheduled_slot(rest) if rest.positive?
    rows
  end

  def slot_of(installment)
    {
      installment: installment, due_date: installment.due_date, kind: installment.kind,
      note: Erp::ReceivableInstallment::KIND_LABELS[installment.kind],
      amount_micros: installment.amount_micros.to_i
    }
  end

  def unscheduled_slot(amount_micros)
    { installment: nil, due_date: nil, kind: nil, note: UNSCHEDULED_NOTE, amount_micros: amount_micros }
  end
end
