class CreateCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_sales_orders do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_customer_id, index: true
      t.bigint :contact_id, index: true
      t.bigint :crm_opportunity_id, index: true
      t.bigint :owner_id, index: true
      # crm_quote_id（来源报价单）在 S1.5 建 crm_quotes 时补加
      t.string :name, null: false
      t.string :order_no, null: false
      t.string :status, default: 'PENDING_CONFIRMATION', null: false
      t.datetime :order_date, null: false
      t.datetime :delivery_date
      t.string :order_currency, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6
      # 金额=整数微分（Twenty 口径，S4 迁移 1:1 直搬）
      t.bigint :order_amount_micros
      t.bigint :cost_amount_micros
      t.bigint :profit_amount_micros
      t.decimal :profit_rate, precision: 6, scale: 2
      t.text :remark
      t.timestamps
    end

    add_index :crm_sales_orders, [:account_id, :order_no], unique: true
    add_index :crm_sales_orders, [:account_id, :status]
    add_index :crm_sales_orders, [:account_id, :order_date]
    add_foreign_key :crm_sales_orders, :crm_customers, column: :crm_customer_id, on_delete: :nullify
    add_foreign_key :crm_sales_orders, :contacts, column: :contact_id, on_delete: :nullify
    add_foreign_key :crm_sales_orders, :crm_opportunities, column: :crm_opportunity_id, on_delete: :nullify
    add_foreign_key :crm_sales_orders, :users, column: :owner_id, on_delete: :nullify

    # 客户成交汇总（CRM_SPEC §12.3 系统计算字段，由订单增改删回写，排除 CANCELLED）
    change_table :crm_customers, bulk: true do |t|
      t.bigint :deal_total_amount_micros
      t.integer :deal_order_count, default: 0, null: false
      t.datetime :first_deal_at
      t.datetime :last_deal_at
    end
  end
end
