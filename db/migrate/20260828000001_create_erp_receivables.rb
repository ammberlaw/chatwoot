class CreateErpReceivables < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_receivables do |t|
      t.references :account, null: false, index: true
      t.string :receivable_no, null: false          # AR-YYYYMMDD-NN
      t.bigint :crm_sales_order_id, index: true     # 一单一账（唯一）
      t.bigint :crm_customer_id, null: false, index: true
      t.string :currency, null: false, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6, null: false, default: 1
      t.bigint :total_amount_micros, null: false, default: 0   # 应收总额（原币）
      t.bigint :received_amount_micros, null: false, default: 0 # 已收（原币），只经核销代码路径维护
      t.string :status, null: false, default: 'UNPAID'         # UNPAID/PARTIAL/PAID
      t.bigint :owner_id                                        # 归属业务员（催款责任人）
      t.text :remark
      t.timestamps

      t.index %i[account_id receivable_no], unique: true
      t.index %i[account_id status]
    end
    add_index :erp_receivables, %i[account_id crm_sales_order_id], unique: true, where: 'crm_sales_order_id IS NOT NULL',
                                                                   name: 'index_erp_receivables_on_account_and_order'
  end
end
