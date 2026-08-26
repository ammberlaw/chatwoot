# 凭证过账与红冲：会计系统里唯一改凭证状态的入口，硬规则都在这里兜。
#
# 过账：借贷本位币必平、至少两行、只有 DRAFT 能过账。
# 红冲：POSTED 凭证不许改删，错账一键生成方向相反的红冲凭证（直接记账生效），两张互相引用留痕。
class Erp::VoucherPostingService
  class Error < StandardError; end

  def initialize(voucher, user)
    @voucher = voucher
    @user = user
  end

  def post!
    raise Error, "凭证「#{@voucher.voucher_no}」不是待过账状态，不能过账" unless @voucher.status == Erp::Voucher::DRAFT

    @voucher.refresh_totals!
    @voucher.reload
    raise Error, '凭证至少要有一借一贷两行分录' if @voucher.lines.count < 2
    raise Error, "借贷不平：借方 #{fmt(@voucher.total_debit_micros)} / 贷方 #{fmt(@voucher.total_credit_micros)}" unless @voucher.balanced?

    @voucher.update!(status: Erp::Voucher::POSTED, posted_by_id: @user.id, posted_at: Time.current)
    @voucher
  end

  def reverse!
    raise Error, '只有已记账的凭证才需要红冲' unless @voucher.status == Erp::Voucher::POSTED
    raise Error, "该凭证已被 #{@voucher.reversed_by.voucher_no} 红冲过" if @voucher.reversed_by.present?

    reversal = nil
    ActiveRecord::Base.transaction do
      reversal = @voucher.account.erp_vouchers.create!(
        voucher_date: Time.zone.today,
        summary: "红冲 #{@voucher.voucher_no}#{@voucher.summary.present? ? "：#{@voucher.summary}" : ''}",
        status: Erp::Voucher::POSTED,
        prepared_by_id: @user.id,
        posted_by_id: @user.id,
        posted_at: Time.current,
        reversal_of_id: @voucher.id,
        source_type: @voucher.source_type,
        source_id: @voucher.source_id,
        lines_attributes: reversed_lines_attributes
      )
      reversal.refresh_totals!
    end
    reversal
  end

  private

  def reversed_lines_attributes
    @voucher.lines.map do |line|
      {
        ledger_account_id: line.ledger_account_id,
        direction: line.direction == Erp::VoucherLine::DEBIT ? Erp::VoucherLine::CREDIT : Erp::VoucherLine::DEBIT,
        summary: line.summary,
        amount_micros: line.amount_micros,
        currency: line.currency,
        exchange_rate: line.exchange_rate,
        position: line.position,
        crm_customer_id: line.crm_customer_id,
        mes_supplier_id: line.mes_supplier_id,
        crm_sales_order_id: line.crm_sales_order_id,
        department_id: line.department_id,
        member_id: line.member_id,
        # 现金流量项目必须一起带过来：不带的话红冲分录会按对方科目重新推断，
        # 大概率落到另一个项目，现金流量表上原单与红冲各算一笔、非但不抵消还翻倍。
        cash_flow_item: line.cash_flow_item
      }
    end
  end

  def fmt(micros)
    format('%.2f', micros.to_i / 1_000_000.0)
  end
end
