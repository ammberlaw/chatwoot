class AddCrmRoleToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    # CRM 角色（仅销售/管理条线）：manager=主管、sales=业务员。
    # 空 = 非 CRM 人员（其他部门），进不去 CRM。系统管理员(administrator)自动全权，与本字段无关。
    add_column :account_users, :crm_role, :string
    add_index :account_users, [:account_id, :crm_role],
              name: 'index_account_users_on_account_id_and_crm_role'
  end
end
