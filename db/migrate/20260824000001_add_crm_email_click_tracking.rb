class AddCrmEmailClickTracking < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_email_clicks do |t|
      t.references :crm_email, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :url
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    # 聚合列（仿 open_count 等），供列表/追踪视图直接读，不用逐行 count。
    add_column :crm_emails, :click_count, :integer, null: false, default: 0
    add_column :crm_emails, :first_clicked_at, :datetime
    add_column :crm_emails, :last_clicked_at, :datetime
  end
end
