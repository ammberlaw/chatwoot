# 文档中心资料板块：9 个默认板块（销售资料/公司制度/流程/培训资料/单证与报关/
# 行政/财务/采购与供应商/生产管理），每板块可配置可见部门（空 = 全员可见）。
class CreateCrmDocSections < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_doc_sections do |t|
      t.references :account, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.bigint :department_ids, array: true, default: [], null: false
      t.timestamps
    end
    add_index :crm_doc_sections, [:account_id, :name], unique: true

    add_column :crm_knowledge_docs, :section_id, :bigint
    add_index :crm_knowledge_docs, [:account_id, :section_id]
    add_foreign_key :crm_knowledge_docs, :crm_doc_sections, column: :section_id, on_delete: :nullify
  end
end
