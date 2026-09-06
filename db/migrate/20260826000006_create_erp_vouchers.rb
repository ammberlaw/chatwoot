class CreateErpVouchers < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_vouchers do |t|
      t.references :account, null: false, index: true
      t.string :voucher_no, null: false        # 记-YYYY-MM-####（期间内连续）
      t.string :period, null: false            # YYYY-MM，账簿/结账按期间收口
      t.date :voucher_date, null: false
      t.string :status, null: false, default: 'DRAFT' # DRAFT 待过账 / POSTED 已记账 / VOID 作废
      t.string :summary                        # 凭证事由（行上另有逐行摘要）
      t.string :source_type                    # 来源业务单据类型，手工凭证为空
      t.bigint :source_id
      t.bigint :prepared_by_id                 # 制单
      t.bigint :posted_by_id                   # 记账（过账人）
      t.datetime :posted_at
      t.bigint :reversal_of_id                 # 本张是哪张凭证的红冲
      t.bigint :total_debit_micros, null: false, default: 0  # 本位币合计，列表直接取不做 N+1
      t.bigint :total_credit_micros, null: false, default: 0
      t.integer :attachment_count, null: false, default: 0   # 附件张数（中式凭证要写「附单据X张」）
      t.text :remark
      t.timestamps

      t.index %i[account_id voucher_no], unique: true
      t.index %i[account_id period]
      t.index %i[account_id voucher_date]
      t.index %i[account_id status]
      t.index %i[source_type source_id]
    end

    add_foreign_key :erp_vouchers, :erp_vouchers, column: :reversal_of_id, on_delete: :nullify
  end
end
