class CreateCrmEmails < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_emails do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_customer_id, index: true
      t.bigint :contact_id, index: true
      t.bigint :owner_id, index: true
      # 去重映射：镜像自 Chatwoot 消息时记录来源 message id（对应 Twenty crm_email_imap_map）
      t.bigint :chatwoot_message_id
      t.string :subject
      t.string :folder, default: 'INBOX', null: false
      t.boolean :is_read, default: false, null: false
      t.string :from_address
      t.text :to_address
      t.text :cc_address
      t.text :bcc_address
      t.datetime :email_date
      t.text :body_html
      t.text :body
      t.boolean :send_now, default: false, null: false
      t.string :send_status, default: 'DRAFT', null: false
      t.text :send_error
      t.decimal :reply_latency_hours, precision: 10, scale: 2
      t.timestamps
    end

    add_index :crm_emails, [:account_id, :folder]
    add_index :crm_emails, [:account_id, :is_read]
    add_index :crm_emails, [:account_id, :email_date]
    add_index :crm_emails, :chatwoot_message_id, unique: true, where: 'chatwoot_message_id IS NOT NULL'
    add_foreign_key :crm_emails, :crm_customers, column: :crm_customer_id, on_delete: :nullify
    add_foreign_key :crm_emails, :contacts, column: :contact_id, on_delete: :nullify
    add_foreign_key :crm_emails, :users, column: :owner_id, on_delete: :nullify
  end
end
