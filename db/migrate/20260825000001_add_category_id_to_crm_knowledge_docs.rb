class AddCategoryIdToCrmKnowledgeDocs < ActiveRecord::Migration[7.1]
  # 文档按「文件夹 ID」归属（而非分类名），以支持任意层级 + 同名子文件夹（像电脑文件夹）。
  def up
    unless column_exists?(:crm_knowledge_docs, :category_id)
      add_column :crm_knowledge_docs, :category_id, :bigint
      add_index :crm_knowledge_docs, :category_id
    end

    # 回填：旧数据分类名在同板块内唯一，可无歧义映射到具体分类记录。
    execute <<~SQL.squish
      UPDATE crm_knowledge_docs d
      SET category_id = c.id
      FROM crm_knowledge_categories c
      WHERE d.category IS NOT NULL AND d.category <> ''
        AND c.account_id = d.account_id
        AND c.name = d.category
        AND COALESCE(c.section_id, 0) = COALESCE(d.section_id, 0)
        AND (
          (d.scope = 'PERSONAL' AND c.user_id = d.owner_id)
          OR (d.scope <> 'PERSONAL' AND c.user_id IS NULL)
        )
    SQL

    # 分类唯一约束：从「同板块内唯一」放宽为「同一父文件夹内唯一」，允许跨层/跨父重名。
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_company_name' if index_name_exists?(:crm_knowledge_categories, 'idx_crm_knowledge_cats_company_name')
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_personal_name' if index_name_exists?(:crm_knowledge_categories, 'idx_crm_knowledge_cats_personal_name')
    execute <<~SQL.squish
      CREATE UNIQUE INDEX idx_crm_knowledge_cats_company_name
      ON crm_knowledge_categories (account_id, COALESCE(section_id, 0), COALESCE(parent_id, 0), name)
      WHERE user_id IS NULL
    SQL
    execute <<~SQL.squish
      CREATE UNIQUE INDEX idx_crm_knowledge_cats_personal_name
      ON crm_knowledge_categories (account_id, user_id, COALESCE(parent_id, 0), name)
      WHERE user_id IS NOT NULL
    SQL

    unless foreign_key_exists?(:crm_knowledge_docs, :crm_knowledge_categories, column: :category_id)
      add_foreign_key :crm_knowledge_docs, :crm_knowledge_categories, column: :category_id, on_delete: :nullify
    end
  end

  def down
    remove_foreign_key :crm_knowledge_docs, column: :category_id if foreign_key_exists?(:crm_knowledge_docs, :crm_knowledge_categories, column: :category_id)

    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_company_name' if index_name_exists?(:crm_knowledge_categories, 'idx_crm_knowledge_cats_company_name')
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_personal_name' if index_name_exists?(:crm_knowledge_categories, 'idx_crm_knowledge_cats_personal_name')
    execute <<~SQL.squish
      CREATE UNIQUE INDEX idx_crm_knowledge_cats_company_name
      ON crm_knowledge_categories (account_id, COALESCE(section_id, 0), name)
      WHERE user_id IS NULL
    SQL
    execute <<~SQL.squish
      CREATE UNIQUE INDEX idx_crm_knowledge_cats_personal_name
      ON crm_knowledge_categories (account_id, user_id, name)
      WHERE user_id IS NOT NULL
    SQL

    remove_column :crm_knowledge_docs, :category_id
  end
end
