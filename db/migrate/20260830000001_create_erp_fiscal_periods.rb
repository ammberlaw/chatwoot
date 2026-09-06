class CreateErpFiscalPeriods < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_fiscal_periods do |t|
      t.references :account, null: false, index: true
      t.string :period, null: false               # YYYY-MM
      t.string :status, null: false, default: 'OPEN' # OPEN / CLOSED
      t.datetime :closed_at
      t.bigint :closed_by_id
      t.bigint :closing_voucher_id                # 期末结转凭证（损益→本年利润）
      t.datetime :reopened_at                     # 反结账留痕（限管理员）
      t.bigint :reopened_by_id
      t.text :remark
      t.timestamps

      t.index %i[account_id period], unique: true
    end
  end
end
