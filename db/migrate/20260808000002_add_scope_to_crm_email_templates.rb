class AddScopeToCrmEmailTemplates < ActiveRecord::Migration[7.1]
  def change
    # 现有模板本就全公司共用，默认置为企业模版(COMPANY)；个人模版(PERSONAL)带 owner。
    add_column :crm_email_templates, :scope, :string, null: false, default: 'COMPANY'
    add_column :crm_email_templates, :owner_id, :bigint
    add_index :crm_email_templates, [:account_id, :scope]
    add_index :crm_email_templates, :owner_id
  end
end
