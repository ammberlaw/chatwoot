class CreateCrmEmailDistributions < ActiveRecord::Migration[7.1]
  def change
    # 邮件内部分发：把一封邮件（正文+附件）分发给公司内部同事查看，站内流转、不外发。每分发人一行 + 记录。
    create_table :crm_email_distributions do |t|
      t.bigint :account_id, null: false
      t.bigint :crm_email_id, null: false
      t.bigint :from_user_id, null: false
      t.bigint :to_user_id, null: false
      t.text :note
      t.datetime :read_at
      t.timestamps
    end
    add_index :crm_email_distributions, [:account_id, :to_user_id]
    add_index :crm_email_distributions, :crm_email_id
    add_index :crm_email_distributions, [:crm_email_id, :to_user_id],
              unique: true, name: 'idx_crm_email_dist_email_user'
  end
end
