class BackfillApprovalDepartmentSnapshot < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE oa_approval_requests r SET department_name_snapshot = d.name
      FROM org_departments d WHERE r.department_id = d.id AND r.account_id = d.account_id AND r.department_name_snapshot IS NULL
    SQL
  end

  def down; end
end
