class AllowKnowledgeFolderNamesAfterDiscard < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  COMPANY_COLUMNS = 'account_id, COALESCE(section_id, 0::bigint), COALESCE(parent_id, 0::bigint), name'.freeze
  PERSONAL_COLUMNS = 'account_id, user_id, COALESCE(parent_id, 0::bigint), name'.freeze

  def up
    add_index :crm_knowledge_categories, COMPANY_COLUMNS, unique: true, where: 'user_id IS NULL AND discarded_at IS NULL',
                                                        name: 'idx_crm_knowledge_cats_company_kept', algorithm: :concurrently
    add_index :crm_knowledge_categories, PERSONAL_COLUMNS, unique: true, where: 'user_id IS NOT NULL AND discarded_at IS NULL',
                                                         name: 'idx_crm_knowledge_cats_personal_kept', algorithm: :concurrently
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_company_name', algorithm: :concurrently
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_personal_name', algorithm: :concurrently
  end

  def down
    # Recreating the old constraints deliberately fails on conflicting names rather than deleting archived folders.
    add_index :crm_knowledge_categories, COMPANY_COLUMNS, unique: true, where: 'user_id IS NULL',
                                                        name: 'idx_crm_knowledge_cats_company_name', algorithm: :concurrently
    add_index :crm_knowledge_categories, PERSONAL_COLUMNS, unique: true, where: 'user_id IS NOT NULL',
                                                         name: 'idx_crm_knowledge_cats_personal_name', algorithm: :concurrently
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_company_kept', algorithm: :concurrently
    remove_index :crm_knowledge_categories, name: 'idx_crm_knowledge_cats_personal_kept', algorithm: :concurrently
  end
end
