class CreateCrmMailAccountsAndTemplates < ActiveRecord::Migration[7.1]
  def change
    # 发信邮箱账户（一人可多个，CRM_SPEC §12.1 mailAccount）
    create_table :crm_mail_accounts do |t|
      t.references :account, null: false, index: true
      t.bigint :owner_id, index: true
      t.string :name, null: false
      t.string :email_address, null: false
      t.string :provider, default: 'TENCENT_EXMAIL', null: false
      t.string :smtp_host
      t.integer :smtp_port
      t.string :smtp_user
      t.string :smtp_password
      t.boolean :use_ssl, default: true, null: false
      t.boolean :is_active, default: true, null: false
      t.text :signature
      t.timestamps
    end
    add_foreign_key :crm_mail_accounts, :users, column: :owner_id, on_delete: :nullify

    # 邮件模板（CRM_SPEC §12.1 emailTemplate）
    create_table :crm_email_templates do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.string :category, default: 'DEVELOPMENT', null: false
      t.string :subject_template
      t.text :body
      t.string :description
      t.timestamps
    end
  end
end
