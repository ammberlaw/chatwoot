class ScopeKnowledgeCategoriesBySection < ActiveRecord::Migration[7.1]
  # 公司分类此前只按账号存，看板列被所有库/板块共用。改为按板块（section）隔离：
  # 销售资料 / 公司制度 / 流程 / 培训资料 … 各自独立的分类列。个人分类不受影响。
  def up
    add_column :crm_knowledge_categories, :section_id, :bigint
    add_index :crm_knowledge_categories, :section_id

    # 存量公司分类过去全局共用，实际用于「销售资料」板块；归到该板块，避免散落到文档中心其它板块。
    execute(<<~SQL.squish)
      UPDATE crm_knowledge_categories c
      SET section_id = s.id
      FROM crm_doc_sections s
      WHERE s.account_id = c.account_id AND s.name = '销售资料' AND c.user_id IS NULL
    SQL

    # 公司分类唯一性改为按板块（section_id 为空按 0 归一，聚合视图内也不重名）。
    remove_index :crm_knowledge_categories, name: :idx_crm_knowledge_cats_company_name
    execute(<<~SQL.squish)
      CREATE UNIQUE INDEX idx_crm_knowledge_cats_company_name
        ON crm_knowledge_categories (account_id, COALESCE(section_id, 0), name)
        WHERE user_id IS NULL
    SQL
  end

  def down
    remove_index :crm_knowledge_categories, name: :idx_crm_knowledge_cats_company_name
    execute(<<~SQL.squish)
      CREATE UNIQUE INDEX idx_crm_knowledge_cats_company_name
        ON crm_knowledge_categories (account_id, name)
        WHERE user_id IS NULL
    SQL
    remove_index :crm_knowledge_categories, :section_id
    remove_column :crm_knowledge_categories, :section_id
  end
end
