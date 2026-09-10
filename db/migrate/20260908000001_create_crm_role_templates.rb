# 岗位权限模板：管理员自定义「一个岗位 = 系统角色 + 可进系统模块 + MES 岗位 + 财务权限」，
# 在成员权限页一键套用到某个成员。模板可增删改，不写死在代码里。
class CreateCrmRoleTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_role_templates do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.string :system_role, default: '', null: false
      t.string :module_access, array: true, default: [], null: false
      t.string :mes_roles, array: true, default: [], null: false
      t.boolean :crm_finance, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps

      t.index [:account_id, :position], name: 'index_crm_role_templates_on_account_and_position'
      t.index [:account_id, :name], unique: true, name: 'index_crm_role_templates_on_account_and_name'
    end
  end
end
