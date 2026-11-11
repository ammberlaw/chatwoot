module Erp::SettlementRecord
  extend ActiveSupport::Concern

  included do
    validates :bank_charge_micros, numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :exchange_rate, numericality: { greater_than: 0 }
    validate :validate_settlement_cash_account
    before_destroy :guard_settlement_destroy, prepend: true
  end

  # 已记账凭证须先红冲，再允许单据作废回滚台账和资金流水。
  def ensure_voucher_reversed!
    voucher = account.erp_vouchers.where(source_type: self.class.name, source_id: id)
                     .where.not(status: Erp::Voucher::VOID).order(:id).last
    return if voucher.nil? || voucher.status != Erp::Voucher::POSTED || voucher.reversal_of_id.present? || voucher.reversed_by.present?

    raise Erp::AutoVoucherService::Error, "本单凭证 #{voucher.voucher_no} 已记账，请先红冲凭证再作废单据"
  end

  private

  def validate_settlement_cash_account
    return if cash_account_id.blank?

    cash = account.erp_cash_accounts.find_by(id: cash_account_id)
    if cash.nil?
      errors.add(:base, '资金账户不存在或不属于本账套')
    elsif cash.currency != currency
      errors.add(:base, "资金账户是 #{cash.currency}，单据是 #{currency}，请选择同币种账户")
    elsif !cash.is_active? && (new_record? || will_save_change_to_cash_account_id?)
      errors.add(:base, '该资金账户已停用，请选择启用中的账户')
    end
  end

  # 与改单的行锁互斥；锁内重新核对，不允许遗留没有主单的流水或凭证。
  def guard_settlement_destroy
    lock!
    date = respond_to?(:received_at) ? received_at : paid_at
    if Erp::FiscalPeriod.closed?(account, date.strftime('%Y-%m'))
      errors.add(:base, '单据所属期间已结账，不能删除')
      throw :abort
    end
    return unless settlement_history?

    errors.add(:base, '该单据已有核销、资金流水或凭证，不能删除，请使用作废保留记录')
    throw :abort
  end

  def settlement_history?
    source = { source_type: self.class.name, source_id: id }
    allocations.exists? || account.erp_cash_transactions.exists?(source) || account.erp_vouchers.exists?(source)
  end
end
