# 费用报销打款：员工照旧在 OA 提「费用报销」审批，审批通过后这张单承接财务侧的付款与入账。
# 一张审批单只允许打款一次（唯一索引兜底），作废后可重打。
class CreateErpExpensePayouts < ActiveRecord::Migration[7.1]
  def change
    create_payouts_table
    add_payout_indexes
    add_payout_foreign_keys
  end

  private

  def create_payouts_table
    create_table :erp_expense_payouts do |t|
      t.references :account, null: false, index: true
      t.bigint :oa_approval_request_id, null: false
      t.string :payout_no, null: false
      t.bigint :amount_micros, null: false
      t.bigint :expense_ledger_account_id, null: false
      t.bigint :cash_account_id, null: false
      t.bigint :crm_sales_order_id
      t.string :cost_type
      t.date :paid_at, null: false
      t.string :status, null: false, default: 'NORMAL'
      t.text :remark
      t.bigint :recorded_by_id
      t.timestamps
    end
  end

  def add_payout_indexes
    add_index :erp_expense_payouts, [:account_id, :payout_no], unique: true
    add_index :erp_expense_payouts, [:account_id, :paid_at]
    add_index :erp_expense_payouts, :oa_approval_request_id
    add_index :erp_expense_payouts, :crm_sales_order_id
    # 同一张审批单只能有一条未作废的打款单——防并发/重复提交把钱打两遍。
    add_index :erp_expense_payouts, [:account_id, :oa_approval_request_id],
              unique: true, where: "status <> 'VOID'", name: 'uniq_erp_expense_payout_live_request'
  end

  def add_payout_foreign_keys
    add_foreign_key :erp_expense_payouts, :oa_approval_requests, column: :oa_approval_request_id, on_delete: :cascade
    add_foreign_key :erp_expense_payouts, :erp_ledger_accounts, column: :expense_ledger_account_id
    add_foreign_key :erp_expense_payouts, :erp_cash_accounts, column: :cash_account_id
    add_foreign_key :erp_expense_payouts, :crm_sales_orders, column: :crm_sales_order_id, on_delete: :nullify
  end
end
