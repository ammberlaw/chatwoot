# 员工档案关联系统账号：离职交接（客户退公海/转移、个人文档归档、角色置无）依赖此关联。
class AddUserToCrmEmployees < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_employees, :user_id, :bigint
    add_index :crm_employees, [:account_id, :user_id], unique: true, where: 'user_id IS NOT NULL'
  end
end
