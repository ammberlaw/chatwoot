class CreateErpOrderCosts < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_order_costs do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_sales_order_id, null: false, index: true
      t.string :cost_type, null: false, default: 'MATERIAL' # MATERIAL/PROCESS/FREIGHT/COMMISSION/OTHER
      t.bigint :amount_micros, null: false
      t.string :currency, null: false, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6, null: false, default: 1
      t.date :happened_at
      t.string :source_type          # 来源：应付台账/付款单/手工
      t.bigint :source_id
      t.bigint :mes_supplier_id
      t.text :remark
      t.bigint :created_by_id
      t.timestamps

      t.index %i[account_id cost_type]
    end
  end
end
