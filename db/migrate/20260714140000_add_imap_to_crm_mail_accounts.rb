class AddImapToCrmMailAccounts < ActiveRecord::Migration[7.1]
  def change
    # 业务员邮箱收件（IMAP）：默认关闭；host/port 留空则按 provider 推导；
    # 认证复用 smtp_password（企业邮多为同一授权码）。imap_synced_at 记录上次拉取时点。
    add_column :crm_mail_accounts, :imap_enabled, :boolean, null: false, default: false
    add_column :crm_mail_accounts, :imap_host, :string
    add_column :crm_mail_accounts, :imap_port, :integer
    add_column :crm_mail_accounts, :imap_ssl, :boolean, null: false, default: true
    add_column :crm_mail_accounts, :imap_synced_at, :datetime

    # 收信去重：邮件 Message-ID（账号内唯一，仅非空时约束）。
    add_column :crm_emails, :message_id, :string
    add_index :crm_emails, [:account_id, :message_id], unique: true,
              where: '(message_id IS NOT NULL)', name: 'index_crm_emails_on_account_id_and_message_id'
  end
end
