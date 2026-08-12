class CreateTiktokShops < ActiveRecord::Migration[7.1]
  def change
    create_table :tiktok_shops do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false                    # 店铺显示名（如 KidzTab PH）
      t.string :region                                # 市场/地区（可选，如 PH）
      t.boolean :active, null: false, default: true   # 停用后不再出现在录入下拉（软隐藏，保留历史数据）
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :tiktok_shops, %i[account_id position]
    add_index :tiktok_shops, %i[account_id name], unique: true, name: 'idx_tiktok_shops_name'
    add_foreign_key :tiktok_shops, :accounts, column: :account_id, on_delete: :cascade
  end
end
