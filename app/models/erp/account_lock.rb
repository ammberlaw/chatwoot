# ERP 会计动作的账套级 advisory 锁：把「读状态/读余额 → 校验 → 写入」串行化，
# 配合事务内复检，杜绝并发下的重复过账/重复红冲/超额核销/结账竞态/单例凭证重复生成等错账。
# 事务级锁：事务提交或回滚时自动释放，无需手工解锁（与 Erp::SequenceAllocator 同机制）。
module Erp::AccountLock
  module_function

  # 在一个事务内先取 (account_id, key) 的 pg_advisory_xact_lock，再执行 block。
  # 已在外层事务中时复用该事务（advisory_xact_lock 作用域=最外层事务）。
  # 用法：Erp::AccountLock.with_account_lock(account.id, "voucher:#{voucher.id}") { ... }
  def with_account_lock(account_id, key)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(
          ['SELECT pg_advisory_xact_lock(hashtext(?))', "erp:#{account_id}:#{key}"]
        )
      )
      yield
    end
  end
end
