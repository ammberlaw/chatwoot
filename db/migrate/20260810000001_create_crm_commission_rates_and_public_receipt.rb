class CreateCrmCommissionRatesAndPublicReceipt < ActiveRecord::Migration[7.1]
  def change
    # 提成点按产品品类配置：rate 存百分数（3.0000 = 3%），提成工资 = 提成基数 × rate / 100。
    create_table :crm_commission_rates do |t|
      t.bigint :account_id, null: false
      t.string :product_category, null: false
      t.decimal :rate, precision: 7, scale: 4, null: false, default: 0
      t.timestamps
    end
    add_index :crm_commission_rates, [:account_id, :product_category],
              unique: true, name: 'idx_crm_commission_rates_category'

    # 对公收款：该行算提成基数时销售额RMB需 ÷1.13 扣增值税。业务/财务逐行勾选。
    add_column :crm_commission_items, :is_public_receipt, :boolean, null: false, default: false
  end
end
