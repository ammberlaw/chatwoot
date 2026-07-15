class AddDiscardToCrmKnowledgeDocs < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_knowledge_docs, :discarded_at, :datetime
    add_column :crm_knowledge_docs, :discarded_by_id, :bigint
    add_index :crm_knowledge_docs, [:account_id, :discarded_at]
  end
end
