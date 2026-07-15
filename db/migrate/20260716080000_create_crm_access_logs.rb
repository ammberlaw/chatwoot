# 敏感数据访问日志：记录谁在何时查看了员工档案/薪资配置（写操作由 audited 审计另行记录）。
class CreateCrmAccessLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_access_logs do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :resource_type, null: false
      t.bigint :resource_id
      t.string :action, null: false

      t.timestamps
    end
    add_index :crm_access_logs, [:account_id, :resource_type, :resource_id, :created_at], name: 'idx_crm_access_logs_on_resource'
  end
end
