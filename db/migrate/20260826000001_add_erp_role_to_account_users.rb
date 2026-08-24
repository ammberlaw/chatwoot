class AddErpRoleToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :erp_role, :string
    add_index :account_users, %i[account_id erp_role]
  end
end
