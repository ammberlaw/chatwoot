# 资料分类分两层：user_id 空=公司分类（管理员/负责人维护），非空=个人分类（本人自建自管）。
# 同时删除历史预置分类（产品目录/FAQ 等），新账号不再播种，看板列由使用者自建。
class PersonalKnowledgeCategories < ActiveRecord::Migration[7.1]
  PRESET_NAMES = %w[产品目录 FAQ 售后政策 报价模板 公司资质 操作手册 产品规格书 收款账户].freeze

  def up
    add_column :crm_knowledge_categories, :user_id, :bigint
    add_index :crm_knowledge_categories, :user_id
    remove_index :crm_knowledge_categories, [:account_id, :name]
    add_index :crm_knowledge_categories, [:account_id, :name],
              unique: true, where: 'user_id IS NULL', name: 'idx_crm_knowledge_cats_company_name'
    add_index :crm_knowledge_categories, [:account_id, :user_id, :name],
              unique: true, where: 'user_id IS NOT NULL', name: 'idx_crm_knowledge_cats_personal_name'

    quoted = PRESET_NAMES.map { |name| "'#{name}'" }.join(', ')
    execute "DELETE FROM crm_knowledge_categories WHERE name IN (#{quoted})"
  end

  def down
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_company_name'
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_personal_name'
    remove_column :crm_knowledge_categories, :user_id
    add_index :crm_knowledge_categories, [:account_id, :name], unique: true
  end
end
