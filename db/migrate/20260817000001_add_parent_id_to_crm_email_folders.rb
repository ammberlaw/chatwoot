class AddParentIdToCrmEmailFolders < ActiveRecord::Migration[7.1]
  def change
    # 文件夹自嵌套：parent_id 指向上级文件夹，实现无限层级子文件夹。
    add_column :crm_email_folders, :parent_id, :bigint
    add_index :crm_email_folders, :parent_id
  end
end
