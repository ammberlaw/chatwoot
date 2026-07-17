class ReplaceDocSectionDeptVisibilityWithViewers < ActiveRecord::Migration[7.1]
  # 板块可见性从「可见部门白名单」改为「可见成员白名单」：像人事/财务资料只给两三个人看。
  # 空 = 全员可见。旧的 department_ids 依赖 org 部门归属（多未维护，导致普通账号看不到文档），一并弃用。
  # 迁移后所有板块 viewer_ids 为空=全员可见，管理员再对少数敏感板块指定可见成员。
  def up
    add_column :crm_doc_sections, :viewer_ids, :bigint, array: true, default: [], null: false
    remove_column :crm_doc_sections, :department_ids
  end

  def down
    add_column :crm_doc_sections, :department_ids, :bigint, array: true, default: [], null: false
    remove_column :crm_doc_sections, :viewer_ids
  end
end
