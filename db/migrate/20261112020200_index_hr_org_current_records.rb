class IndexHrOrgCurrentRecords < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :crm_employee_comps, [:account_id, :owner_id], unique: true,
              where: 'active = TRUE AND owner_id IS NOT NULL', name: 'idx_current_employee_comp', algorithm: :concurrently
    add_index :org_memberships, [:account_id, :user_id], unique: true,
              where: 'is_primary = TRUE', name: 'idx_primary_org_membership', algorithm: :concurrently
  end
end
