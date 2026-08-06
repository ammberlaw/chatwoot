class CreateCrmOptionItems < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_option_items do |t|
      t.bigint :account_id, null: false
      t.string :category, null: false            # 'customer_group' | 'customer_source'
      t.string :name, null: false                # 显示名（中文）
      t.string :code, null: false                # 稳定标识：存量=原枚举码，新建=生成；客户表按 code 存储
      t.bigint :parent_id                         # 二级层级：子项指向一级项；一级项为 NULL
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true  # 显示/隐藏（软隐藏，不删历史数据引用）
      t.timestamps
    end

    add_index :crm_option_items, %i[account_id category parent_id position], name: 'idx_crm_option_items_tree'
    add_index :crm_option_items, %i[account_id category code], unique: true, name: 'idx_crm_option_items_code'
    add_foreign_key :crm_option_items, :accounts, column: :account_id, on_delete: :cascade
    add_foreign_key :crm_option_items, :crm_option_items, column: :parent_id, on_delete: :cascade
  end
end
