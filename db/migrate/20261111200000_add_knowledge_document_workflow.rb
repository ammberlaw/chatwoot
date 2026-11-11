class AddKnowledgeDocumentWorkflow < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :crm_knowledge_docs, :created_by_id, :bigint
    add_column :crm_knowledge_docs, :updated_by_id, :bigint
    add_column :crm_knowledge_docs, :extract_revision, :integer, default: 0, null: false
    add_index :crm_knowledge_docs, :created_by_id, algorithm: :concurrently
    add_index :crm_knowledge_docs, :updated_by_id, algorithm: :concurrently
    add_foreign_key :crm_knowledge_docs, :users, column: :created_by_id, on_delete: :nullify, validate: false
    add_foreign_key :crm_knowledge_docs, :users, column: :updated_by_id, on_delete: :nullify, validate: false
    validate_foreign_key :crm_knowledge_docs, :users, column: :created_by_id
    validate_foreign_key :crm_knowledge_docs, :users, column: :updated_by_id

    create_table :crm_knowledge_versions do |t|
      t.references :doc, null: false, foreign_key: { to_table: :crm_knowledge_docs, on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.integer :number, null: false
      t.string :note
      t.string :name, null: false
      t.string :summary
      t.text :body
      t.timestamps
    end
    add_index :crm_knowledge_versions, [:doc_id, :number], unique: true
    create_table :crm_knowledge_preferences do |t|
      t.references :doc, null: false, foreign_key: { to_table: :crm_knowledge_docs, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :favorite, default: false, null: false
      t.datetime :last_opened_at
      t.timestamps
    end
    add_index :crm_knowledge_preferences, [:doc_id, :user_id], unique: true, name: 'idx_knowledge_preferences_doc_user'
  end

  def down
    drop_table :crm_knowledge_preferences
    drop_table :crm_knowledge_versions
    remove_column :crm_knowledge_docs, :extract_revision
    remove_reference :crm_knowledge_docs, :updated_by, foreign_key: { to_table: :users }
    remove_reference :crm_knowledge_docs, :created_by, foreign_key: { to_table: :users }
  end
end
