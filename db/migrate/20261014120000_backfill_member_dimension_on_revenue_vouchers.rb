# 应收建账/收款冲减的凭证补上「业务员」核算维度。
#
# 维度本来只挂客户，财务要按业务员看「这个人名下还有多少应收、做了多少收入」就只能回订单查。
# 新出的凭证已经带上了（Erp::AutoVoucherService），这里把存量那几张补齐——
# 不补的话财务打开旧凭证还是只看到客户，以为没生效。
#
# 只补应收科目行和收入行（销项税行挂业务员没有意义）。取不到业务员的跳过，不猜。
class BackfillMemberDimensionOnRevenueVouchers < ActiveRecord::Migration[7.0]
  def up
    Erp::Voucher.where(source_type: 'Erp::Receivable').find_each do |voucher|
      owner_id = Erp::Receivable.find_by(id: voucher.source_id)&.crm_sales_order&.owner_id
      next if owner_id.blank?

      fill(voucher, owner_id)
    end

    Erp::Voucher.where(source_type: 'Erp::ReceiptRecord').find_each do |voucher|
      fill(voucher, receipt_owner_id(voucher.source_id))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # 一笔收款跨了几个业务员就留空——宁可不进维度，也不能算到某一个人头上。
  def receipt_owner_id(receipt_id)
    receipt = Erp::ReceiptRecord.find_by(id: receipt_id)
    return nil if receipt.nil?

    owners = receipt.allocations.includes(receivable: :crm_sales_order)
                    .filter_map { |a| a.receivable&.crm_sales_order&.owner_id }.uniq
    owners.size == 1 ? owners.first : nil
  end

  def fill(voucher, owner_id)
    return if owner_id.blank?

    voucher.lines.includes(:ledger_account).select { |line| fillable?(line) }.each do |line|
      # update_columns：只补一个维度字段，不想触发凭证的任何回调/校验（存量凭证可能已过账）
      line.update_columns(member_id: owner_id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # 只补应收科目行和收入行；销项税行挂业务员没有意义。
  def fillable?(line)
    return false if line.member_id.present?

    account = line.ledger_account
    account&.account_type == 'RECEIVABLE' || account&.code == Erp::AutoVoucherService::REVENUE_CODE
  end
end
