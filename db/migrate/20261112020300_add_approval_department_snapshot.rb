class AddApprovalDepartmentSnapshot < ActiveRecord::Migration[7.1]
  def change
    add_column :oa_approval_requests, :department_name_snapshot, :string
  end
end
