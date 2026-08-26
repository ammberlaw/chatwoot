# 单据编号：AR-20260828-01 这类「前缀-日期-当日序号」。
# 取号的并发与溢出都在 Erp::SequenceAllocator 里处理，本模块只负责拼前缀。
module Erp::DocumentNumber
  module_function

  def next(account, prefix, table, column)
    date_prefix = "#{prefix}-#{Time.zone.today.strftime('%Y%m%d')}-"
    Erp::SequenceAllocator.next_number(account, account.public_send(table), column, date_prefix, 2)
  end
end
