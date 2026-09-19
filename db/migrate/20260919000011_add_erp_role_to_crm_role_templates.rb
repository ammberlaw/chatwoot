class AddErpRoleToCrmRoleTemplates < ActiveRecord::Migration[7.1]
  # 岗位模板要能带 ERP 财务岗位：只给 erp 模块不给 erp_role 的话，套用出来的人
  # 有模块没角色，照样进不去 ERP（can_access_erp? 两个条件都要）。
  def change
    add_column :crm_role_templates, :erp_role, :string
  end
end
