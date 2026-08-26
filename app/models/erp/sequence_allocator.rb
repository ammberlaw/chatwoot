# 单据编号分配（凭证号 / 应收应付收付款单号），并发安全。
#
# 原来的做法是「查最大号 → +1 → 存」，有两个真会在生产触发的毛病，这里一并根治：
#
# 1. **并发撞号**：两个会计同时保存会算出同一个号，唯一索引拦下第二个人，
#    用户看到的是莫名其妙的保存失败（月底一起录凭证必碰）。
#    修法：按 (账户, 号段前缀) 上**事务级 advisory lock**，锁持有到事务提交，
#    同一号段的取号串行化。不落表、不用重试。
#    取号在 before_validation 里跑，而 Rails 的 save 把校验也包在事务内，所以锁的作用域正确。
#
# 2. **序号溢出**：原来按**字符串**排序取最后一条。字符串序里 'AR-20260828-99'
#    排在 'AR-20260828-100' 后面，于是一天满 100 张之后永远算出 100，之后每张都撞号保存失败。
#    修法：序号**按数值取最大**（把前缀后面那截 CAST 成整数），位数不够时自然进位，不会回头。
module Erp::SequenceAllocator
  module_function

  # relation 是该账户下的单据集合（如 account.erp_vouchers）。
  def next_number(account, relation, column, prefix, width)
    lock!(account, prefix)
    format("%s%0#{width.to_i}d", prefix, max_seq(relation, column, prefix) + 1)
  end

  # 事务级 advisory lock：事务提交/回滚时自动释放，不用手工解锁。
  def lock!(account, prefix)
    relation = ActiveRecord::Base
    relation.connection.execute(
      relation.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', "erp_seq:#{account.id}:#{prefix}"])
    )
  end

  # 前缀后面那截是纯数字（单号只由本模块生成，不对外开放编辑），直接 CAST 取最大值。
  def max_seq(relation, column, prefix)
    quoted = ActiveRecord::Base.connection.quote_column_name(column)
    offset = prefix.length + 1
    relation.where("#{quoted} LIKE ?", "#{prefix}%")
            .maximum(Arel.sql("CAST(SUBSTRING(#{quoted} FROM #{offset.to_i}) AS INTEGER)")).to_i
  end
end
