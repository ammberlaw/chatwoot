class AddDefaultMailboxAndEmailSignatures < ActiveRecord::Migration[7.1]
  def change
    # 默认发信邮箱：多邮箱时写邮件默认选中的那个（每个负责人一个默认）。
    add_column :crm_mail_accounts, :is_default, :boolean, default: false, null: false

    # 个性签名库：与邮箱解耦，一人可建多条命名签名，发信时下拉插入，可设默认。
    create_table :crm_email_signatures do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id
      t.string :name, null: false
      t.text :body
      t.boolean :is_default, default: false, null: false
      t.timestamps
    end
    add_index :crm_email_signatures, :account_id
    add_index :crm_email_signatures, :owner_id
  end
end
