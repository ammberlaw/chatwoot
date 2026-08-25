# 单据编号：AR-20260828-01 这类「前缀-日期-当日序号」。
# 并发靠各表 (account_id, 单号) 唯一索引兜底，撞号时上层重试。
module Erp::DocumentNumber
  module_function

  def next(account, prefix, table, column)
    date = Time.zone.today.strftime('%Y%m%d')
    like = "#{prefix}-#{date}-%"
    last = account.public_send(table).where("#{column} LIKE ?", like).order(column).last
    seq = last ? last.public_send(column).split('-').last.to_i + 1 : 1
    format('%<prefix>s-%<date>s-%<seq>02d', prefix: prefix, date: date, seq: seq)
  end
end
