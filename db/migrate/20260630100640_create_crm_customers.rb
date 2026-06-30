class CreateCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_customers do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :account_owner_id

      # Identity
      t.string :name, null: false
      t.string :customer_code

      # Trade geography
      t.string :trade_country
      t.string :trade_region
      t.string :trade_city

      # Classification
      t.string :industry
      t.string :customer_level
      t.string :source_channel
      t.string :currency_preference
      t.string :customer_status
      t.string :customer_group
      t.string :product_group
      t.string :risk_level

      # Follow-up / public pool
      t.datetime :last_follow_up_at
      t.datetime :next_follow_up_at
      t.boolean :is_in_public_pool, null: false, default: false
      t.datetime :public_pool_at

      # Primary contact snapshot
      t.string :primary_contact_name
      t.string :contact_job_title
      t.string :contact_email
      t.string :contact_phone
      t.string :whats_app
      t.string :wechat
      t.string :contact_preference

      t.text :customer_remark

      t.timestamps
    end

    add_index :crm_customers, :account_owner_id
    add_index :crm_customers, [:account_id, :is_in_public_pool]
    add_index :crm_customers, [:account_id, :customer_status]
    add_index :crm_customers, [:account_id, :last_follow_up_at]
    add_index :crm_customers, [:account_id, :customer_code],
              unique: true,
              where: 'customer_code IS NOT NULL',
              name: 'index_crm_customers_on_account_id_and_customer_code'
  end
end
