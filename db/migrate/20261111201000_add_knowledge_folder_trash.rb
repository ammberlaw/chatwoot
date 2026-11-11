class AddKnowledgeFolderTrash < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :crm_knowledge_categories, :discarded_at, :datetime
    add_column :crm_knowledge_categories, :discarded_by_id, :bigint
    add_column :crm_knowledge_categories, :trash_batch, :string
    add_column :crm_knowledge_docs, :trash_batch, :string
    add_index :crm_knowledge_categories, [:account_id, :discarded_at], algorithm: :concurrently
    add_foreign_key :crm_knowledge_categories, :users, column: :discarded_by_id, on_delete: :nullify, validate: false
    validate_foreign_key :crm_knowledge_categories, :users, column: :discarded_by_id
  end

  def down
    remove_reference :crm_knowledge_categories, :discarded_by, foreign_key: { to_table: :users }
    remove_column :crm_knowledge_categories, :discarded_at
    remove_column :crm_knowledge_categories, :trash_batch
    remove_column :crm_knowledge_docs, :trash_batch
  end
end
