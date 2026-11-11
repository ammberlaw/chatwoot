class AddCreatedByToCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :crm_lead_campaigns, :created_by_id, :bigint
    add_index :crm_lead_campaigns, :created_by_id, algorithm: :concurrently
    add_foreign_key :crm_lead_campaigns, :users, column: :created_by_id, on_delete: :nullify, validate: false
    validate_foreign_key :crm_lead_campaigns, :users, column: :created_by_id
  end

  def down
    remove_foreign_key :crm_lead_campaigns, column: :created_by_id
    remove_index :crm_lead_campaigns, :created_by_id, algorithm: :concurrently
    remove_column :crm_lead_campaigns, :created_by_id
  end
end
