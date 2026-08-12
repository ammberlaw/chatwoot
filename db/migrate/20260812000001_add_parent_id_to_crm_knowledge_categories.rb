class AddParentIdToCrmKnowledgeCategories < ActiveRecord::Migration[7.1]
  def change
    # 分类自嵌套：parent_id 指向上级分类，实现「板块→分类→子分类」的三级目录。
    add_column :crm_knowledge_categories, :parent_id, :bigint
    add_index :crm_knowledge_categories, :parent_id
  end
end
