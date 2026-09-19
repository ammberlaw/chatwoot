# 催收预警扫描：应收分期临期/逾期、应付账期到期。
# 财务看板与每日推送共用（对标 Mes::AlertScannerService）。
#
# ⚠️ 核心口径：**已收款按到期日 FIFO 冲抵分期**再算欠多少。
# 不这么算的话，一张「30% 订金 + 70% 尾款」的单子，订金早收了、尾款还没到期，
# 仍会把整笔订金算成逾期天天提醒——催收提醒喊狼来了，业务员就不看了。
# 这与账龄分析（AgingService）是同一套冲抵口径，两处数字必须对得上。
class Erp::AlertScannerService
  DUE_SOON_DAYS = Erp::ReceivableInstallment::DUE_SOON_DAYS # 7

  def initialize(account, today: nil)
    @account = account
    @today = today || Time.zone.today
  end

  # { overdue: [...], due_soon: [...], payable_due: [...] }
  def call
    receivable_rows = scan_receivables
    {
      overdue: receivable_rows.select { |r| r[:days].positive? }.sort_by { |r| -r[:days] },
      due_soon: receivable_rows.select { |r| r[:days] <= 0 }.sort_by { |r| r[:days] },
      payable_due: scan_payables
    }
  end

  private

  def scan_receivables
    scope = @account.erp_receivables
                    .where(status: [Erp::Receivable::UNPAID, Erp::Receivable::PARTIAL])
                    .includes(:installments, :crm_customer, :owner, :crm_sales_order)
    scope.flat_map { |receivable| rows_for(receivable) }
  end

  # 把已收额按到期日先后冲掉分期，剩下的才是真欠款；只留临期与逾期的。
  def rows_for(receivable)
    left = receivable.received_amount_micros.to_i
    ordered_installments(receivable).filter_map do |installment|
      covered = [left, installment.amount_micros.to_i].min
      left -= covered
      open_micros = installment.amount_micros.to_i - covered
      next if open_micros <= 0 || installment.due_date.blank?

      days = (@today - installment.due_date).to_i
      next if days < -DUE_SOON_DAYS # 还早，不打扰

      receivable_row(receivable, installment, open_micros, days)
    end
  end

  # FIFO 顺序与 AgingService 一致：先到期的先冲，没排到期日的排最后。
  def ordered_installments(receivable)
    receivable.installments.sort_by do |item|
      [item.due_date ? 0 : 1, item.due_date || Date.new(9999), item.seq.to_i]
    end
  end

  def receivable_row(receivable, installment, open_micros, days)
    {
      receivable_id: receivable.id, receivable_no: receivable.receivable_no,
      installment_id: installment.id,
      kind_label: Erp::ReceivableInstallment::KIND_LABELS[installment.kind],
      customer_name: receivable.crm_customer&.name,
      order_no: receivable.crm_sales_order&.order_no,
      owner_id: receivable.owner_id,
      owner_name: receivable.owner&.crm_name.presence || receivable.owner&.name,
      currency: receivable.currency,
      open_micros: open_micros,
      base_open_micros: (open_micros * (receivable.exchange_rate.presence || 1).to_d).round,
      due_date: installment.due_date,
      days: days # 正=逾期天数，负=距到期天数
    }
  end

  # 应付账期：到期日已过或 7 天内到期、且还没付清的。
  def scan_payables
    @account.erp_payables
            .where(status: [Erp::Payable::UNPAID, Erp::Payable::PARTIAL])
            .where.not(due_date: nil)
            .where(due_date: ..(@today + DUE_SOON_DAYS))
            .includes(:mes_supplier)
            .map { |payable| payable_row(payable) }
            .sort_by { |row| -row[:days] }
  end

  def payable_row(payable)
    {
      payable_id: payable.id, payable_no: payable.payable_no,
      supplier_name: payable.mes_supplier&.name,
      currency: payable.currency,
      open_micros: payable.outstanding_micros,
      base_open_micros: (payable.outstanding_micros * (payable.exchange_rate.presence || 1).to_d).round,
      due_date: payable.due_date,
      days: (@today - payable.due_date).to_i
    }
  end
end
