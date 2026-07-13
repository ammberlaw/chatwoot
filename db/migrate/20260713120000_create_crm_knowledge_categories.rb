class CreateCrmKnowledgeCategories < ActiveRecord::Migration[7.1]
  KEY_TO_NAME = {
    'PRODUCT_CATALOG' => '产品目录', 'FAQ' => 'FAQ', 'AFTER_SALES' => '售后政策',
    'QUOTE_TEMPLATE' => '报价模板', 'COMPANY_CERT' => '公司资质', 'USER_MANUAL' => '操作手册',
    'PRODUCT_SPEC' => '产品规格书', 'PAYMENT_ACCOUNT' => '收款账户'
  }.freeze

  def up
    create_table :crm_knowledge_categories do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :crm_knowledge_categories, [:account_id, :name], unique: true

    # 存量文档分类由旧枚举 KEY 迁移为中文名，与新默认分类对齐。
    KEY_TO_NAME.each do |key, name|
      execute("UPDATE crm_knowledge_docs SET category = #{connection.quote(name)} WHERE category = #{connection.quote(key)}")
    end
  end

  def down
    drop_table :crm_knowledge_categories
  end
end
