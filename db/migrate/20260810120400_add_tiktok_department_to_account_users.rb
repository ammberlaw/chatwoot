class AddTiktokDepartmentToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :tiktok_department_id, :bigint
    add_index :account_users, :tiktok_department_id
    add_foreign_key :account_users, :tiktok_departments, column: :tiktok_department_id, on_delete: :nullify
  end
end
