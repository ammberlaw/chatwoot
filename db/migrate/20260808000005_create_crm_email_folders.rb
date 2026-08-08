class CreateCrmEmailFolders < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_email_folders do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id, null: false # 个人私有文件夹
      t.string :name, null: false
      t.timestamps
    end
    add_index :crm_email_folders, [:account_id, :owner_id]

    # 邮件所属自定义文件夹（空=在系统文件夹里）。移入文件夹即离开收件箱等系统视图。
    add_column :crm_emails, :crm_email_folder_id, :bigint
    add_index :crm_emails, :crm_email_folder_id
  end
end
