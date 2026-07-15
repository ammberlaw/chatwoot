# 文档中心设置（每账户一行）：指定文档中心负责人。
# 管理员与负责人可在文档中心上传/编辑/删除公司文档，其余成员只读。
class CreateCrmDocCenterSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_doc_center_settings do |t|
      t.references :account, null: false, index: { unique: true }
      t.bigint :owner_id
      t.timestamps
    end
    add_foreign_key :crm_doc_center_settings, :users, column: :owner_id, on_delete: :nullify
  end
end
