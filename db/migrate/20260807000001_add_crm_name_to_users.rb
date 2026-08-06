class AddCrmNameToUsers < ActiveRecord::Migration[7.1]
  def change
    # CRM 专用显示名（英文名）：CRM 界面/对外邮件发件人用；空则回退中文 name。
    add_column :users, :crm_name, :string
  end
end
