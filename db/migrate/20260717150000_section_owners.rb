class SectionOwners < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_doc_sections, :manager_ids, :bigint, array: true, default: [], null: false
    # 把已有的按文档负责人聚合到其所属板块（并集），不丢权限。
    execute <<~SQL.squish
      UPDATE crm_doc_sections s
      SET manager_ids = agg.ids
      FROM (
        SELECT section_id, ARRAY(SELECT DISTINCT unnest(array_agg(m))) AS ids
        FROM crm_knowledge_docs d, unnest(d.manager_ids) AS m
        WHERE d.section_id IS NOT NULL
        GROUP BY section_id
      ) agg
      WHERE s.id = agg.section_id
    SQL
    remove_column :crm_knowledge_docs, :manager_ids
  end

  def down
    add_column :crm_knowledge_docs, :manager_ids, :bigint, array: true, default: [], null: false
    remove_column :crm_doc_sections, :manager_ids
  end
end
