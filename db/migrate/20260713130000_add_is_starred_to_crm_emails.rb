class AddIsStarredToCrmEmails < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_emails, :is_starred, :boolean, default: false, null: false
    add_index :crm_emails, [:account_id, :is_starred], where: 'is_starred', name: 'index_crm_emails_starred'
  end
end
