class AddErpHardeningUniqueIndexes < ActiveRecord::Migration[7.1]
  # ERP 硬化：两条部分唯一索引作为并发兜底（配合 service 层 advisory 锁）。
  # 1) 一张凭证只能被红冲一次——防并发/双击红冲生成两张红冲凭证致多冲一笔。
  # 2) 一个来源单据同时最多一张「草稿」自动凭证——防 auto_voucher「查旧→删→建新」在并发/重试下留双份草稿。
  #    (已过账/已红冲凭证为 POSTED，不受此索引约束；红冲凭证虽复制 source 但状态 POSTED，不冲突。)
  def change
    add_index :erp_vouchers, %i[account_id reversal_of_id],
              unique: true, where: 'reversal_of_id IS NOT NULL',
              name: 'uniq_erp_voucher_reversal'
    add_index :erp_vouchers, %i[account_id source_type source_id],
              unique: true, where: "source_id IS NOT NULL AND status = 'DRAFT'",
              name: 'uniq_erp_voucher_draft_source'
  end
end
