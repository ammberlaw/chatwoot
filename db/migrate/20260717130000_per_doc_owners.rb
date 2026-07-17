class PerDocOwners < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_knowledge_docs, :manager_ids, :bigint, array: true, default: [], null: false
    # 原「文档中心负责人」平移为其账号下所有文档中心公司文档的负责人，权限不缩水。
    execute <<~SQL.squish
      UPDATE crm_knowledge_docs d
      SET manager_ids = ARRAY[s.owner_id]
      FROM crm_doc_center_settings s
      WHERE s.account_id = d.account_id AND s.owner_id IS NOT NULL
        AND d.library = 'GENERAL' AND d.scope = 'COMPANY'
    SQL
    drop_table :crm_doc_center_settings
  end

  def down
    create_table :crm_doc_center_settings do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id
      t.timestamps
      t.index [:account_id], unique: true
    end
    remove_column :crm_knowledge_docs, :manager_ids
  end
end
