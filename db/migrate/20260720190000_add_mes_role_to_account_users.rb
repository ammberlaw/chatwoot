class AddMesRoleToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :mes_role, :string
    add_index :account_users, [:account_id, :mes_role]
  end
end
