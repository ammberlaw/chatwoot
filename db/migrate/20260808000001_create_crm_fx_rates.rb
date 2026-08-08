class CreateCrmFxRates < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_fx_rates do |t|
      t.string :currency, null: false                        # USD / EUR ...
      t.date :quote_date, null: false                        # 牌价发布日期
      t.decimal :rate, precision: 16, scale: 6, null: false  # 折算汇率 = 现汇买入价 / 100（CNY / 1 单位外币）
      t.string :source, null: false, default: 'BOC'          # 数据来源：中国银行
      t.datetime :published_at                               # 中行发布时间
      t.timestamps
    end
    add_index :crm_fx_rates, [:currency, :quote_date], unique: true
  end
end
