class CreateErpFixedAssets < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_fixed_assets do |t|
      t.references :account, null: false, index: true
      t.string :asset_no, null: false                 # FA-YYYYMMDD-NN
      t.string :name, null: false
      t.string :category, null: false, default: 'EQUIPMENT' # EQUIPMENT/VEHICLE/ELECTRONIC/OFFICE/OTHER
      t.date :purchased_at, null: false
      t.bigint :original_value_micros, null: false    # 原值
      t.decimal :residual_rate, precision: 5, scale: 2, null: false, default: 5 # 残值率 %
      t.integer :useful_months, null: false, default: 60 # 折旧年限（月）
      t.bigint :accumulated_depreciation_micros, null: false, default: 0
      t.string :status, null: false, default: 'IN_USE'  # IN_USE/DISPOSED/SCRAPPED
      t.date :disposed_at
      t.bigint :disposal_income_micros, null: false, default: 0
      t.bigint :department_id
      t.bigint :keeper_id
      t.text :remark
      t.timestamps

      t.index %i[account_id asset_no], unique: true
      t.index %i[account_id status]
    end
  end
end
