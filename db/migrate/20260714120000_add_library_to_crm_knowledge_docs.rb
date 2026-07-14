class AddLibraryToCrmKnowledgeDocs < ActiveRecord::Migration[7.1]
  def change
    # 资料库归属：SALES=销售资料(留在 CRM，邮件附件只挑这类)；GENERAL=全公司知识(文档中心)。
    # 既有文档默认归入销售资料库。
    add_column :crm_knowledge_docs, :library, :string, null: false, default: 'SALES'
    add_index :crm_knowledge_docs, [:account_id, :library],
              name: 'index_crm_knowledge_docs_on_account_id_and_library'
  end
end
