class ProtectOrganizationDepartmentLinks < ActiveRecord::Migration[7.1]
  def up
    # Existing orphan references need human reconciliation; NOT VALID preserves those rows
    # while enforcing all future writes and blocking deletion of referenced departments.
    add_foreign_key :crm_employees, :org_departments, column: :department_id, on_delete: :restrict, validate: false
    add_foreign_key :oa_approval_requests, :org_departments, column: :department_id, on_delete: :restrict, validate: false
    add_foreign_key :org_departments, :org_departments, column: :parent_id, on_delete: :restrict, validate: false
    remove_foreign_key :org_memberships, column: :department_id
    add_foreign_key :org_memberships, :org_departments, column: :department_id, on_delete: :restrict, validate: false
  end

  def down
    remove_foreign_key :crm_employees, column: :department_id
    remove_foreign_key :oa_approval_requests, column: :department_id
    remove_foreign_key :org_departments, column: :parent_id
    remove_foreign_key :org_memberships, column: :department_id
    add_foreign_key :org_memberships, :org_departments, column: :department_id, on_delete: :cascade
  end
end
