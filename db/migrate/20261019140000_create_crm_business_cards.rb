# 展会名片：现场只管连拍，回头再批量校对入库（见 Crm::BusinessCard）。
class CreateCrmBusinessCards < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_business_cards do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :owner_id, null: false
      t.string :status, null: false, default: 'PENDING'
      # 展会名称只存文本：展会模块还没上生产，这里不绑它的外键（用户定的轻量关联）。
      t.string :event_name
      t.string :company_name
      t.string :contact_name
      t.string :job_title
      t.string :contact_phone
      t.string :whats_app
      t.string :contact_email
      t.string :website
      t.string :country
      t.text :address
      # OCR 原文：识别字段填错时，校对的人要能对着原文核，不用回头翻照片。
      t.text :raw_text
      # 现场备注：聊了什么、要什么货、报了什么价——这些名片上没有，只能当场记。
      t.text :remark
      t.text :parse_error
      t.datetime :parsed_at
      t.bigint :crm_customer_id
      t.timestamps
    end

    add_index :crm_business_cards, [:account_id, :status]
    add_index :crm_business_cards, :owner_id
    add_index :crm_business_cards, :crm_customer_id
    add_foreign_key :crm_business_cards, :users, column: :owner_id
    add_foreign_key :crm_business_cards, :crm_customers, column: :crm_customer_id, on_delete: :nullify
  end
end
