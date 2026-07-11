class AddCrmFieldsToContacts < ActiveRecord::Migration[7.1]
  def change
    change_table :contacts, bulk: true do |t|
      # A-CRM person 扩展字段（9 个标量，见 CRM_SPEC §3.2）
      t.string :whats_app
      t.string :wechat
      t.boolean :is_primary_contact, default: false, null: false
      t.string :contact_preference
      t.datetime :crm_last_contact_at
      t.text :contact_remark
      t.string :product_category
      t.string :country_region
      t.string :customer_group
      # 联系人 → CRM 客户（一个客户多个联系人，CRM_SPEC §4 / §11）
      t.bigint :crm_customer_id
    end

    add_index :contacts, :crm_customer_id
    add_foreign_key :contacts, :crm_customers, column: :crm_customer_id, on_delete: :nullify
  end
end
