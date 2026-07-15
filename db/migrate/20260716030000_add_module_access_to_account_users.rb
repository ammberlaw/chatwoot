class AddModuleAccessToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :module_access, :text, array: true, default: %w[crm erp mes], null: false
  end
end
