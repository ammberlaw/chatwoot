class CreateCrmProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_products do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.string :sku, null: false
      t.string :category
      t.string :specification
      t.string :unit
      # 金额=整数微分（Twenty 口径），币种统一由 pricing_currency 表达
      t.bigint :cost_price_micros
      t.bigint :sale_price_micros
      t.string :pricing_currency, default: 'USD'
      t.boolean :is_active, default: true, null: false
      t.text :remark
      t.timestamps
    end

    add_index :crm_products, [:account_id, :sku], unique: true
  end
end
