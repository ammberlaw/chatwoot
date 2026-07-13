class AddEmailOpenTracking < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_emails, :tracking_token, :string
    add_column :crm_emails, :open_count, :integer, default: 0, null: false
    add_column :crm_emails, :first_opened_at, :datetime
    add_column :crm_emails, :last_opened_at, :datetime
    add_index :crm_emails, :tracking_token, unique: true, where: 'tracking_token IS NOT NULL'

    create_table :crm_email_opens do |t|
      t.references :crm_email, null: false, foreign_key: { to_table: :crm_emails, on_delete: :cascade }
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
