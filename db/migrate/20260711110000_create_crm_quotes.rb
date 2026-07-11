class CreateCrmQuotes < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_quotes do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_customer_id, index: true
      t.bigint :contact_id, index: true
      t.bigint :crm_opportunity_id, index: true
      t.bigint :owner_id, index: true
      t.string :name, null: false
      t.string :quote_no, null: false
      t.datetime :quote_date
      t.datetime :valid_until
      t.string :status, default: 'DRAFT', null: false
      t.string :quote_currency, default: 'USD'
      t.decimal :exchange_rate, precision: 12, scale: 6
      # 金额=整数微分（Twenty 口径，S4 迁移 1:1 直搬）
      t.bigint :subtotal_micros
      t.bigint :discount_amount_micros
      t.bigint :shipping_fee_micros
      t.bigint :tax_amount_micros
      t.bigint :total_amount_micros
      t.text :remark
      t.timestamps
    end

    add_index :crm_quotes, [:account_id, :quote_no], unique: true
    add_index :crm_quotes, [:account_id, :status]
    add_foreign_key :crm_quotes, :crm_customers, column: :crm_customer_id, on_delete: :nullify
    add_foreign_key :crm_quotes, :contacts, column: :contact_id, on_delete: :nullify
    add_foreign_key :crm_quotes, :crm_opportunities, column: :crm_opportunity_id, on_delete: :nullify
    add_foreign_key :crm_quotes, :users, column: :owner_id, on_delete: :nullify

    create_table :crm_quote_line_items do |t|
      t.references :account, null: false, index: true
      # 明细随报价级联删除（CRM_SPEC §4 唯一的 CASCADE 关系）
      t.bigint :crm_quote_id, null: false, index: true
      t.bigint :crm_product_id, index: true
      t.string :name, null: false
      t.string :product_name_snapshot
      t.string :spec_snapshot
      t.decimal :quantity, precision: 12, scale: 2
      t.bigint :unit_price_micros
      t.bigint :amount_micros
      t.text :remark
      t.timestamps
    end

    add_foreign_key :crm_quote_line_items, :crm_quotes, column: :crm_quote_id, on_delete: :cascade
    add_foreign_key :crm_quote_line_items, :crm_products, column: :crm_product_id, on_delete: :nullify

    # S1.6 预留：销售订单的「来源报价单」
    add_column :crm_sales_orders, :crm_quote_id, :bigint
    add_index :crm_sales_orders, :crm_quote_id
    add_foreign_key :crm_sales_orders, :crm_quotes, column: :crm_quote_id, on_delete: :nullify
  end
end
