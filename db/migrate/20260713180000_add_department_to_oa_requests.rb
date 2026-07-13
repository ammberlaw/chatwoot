class AddDepartmentToOaRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :oa_approval_requests, :department_id, :bigint
    add_index :oa_approval_requests, :department_id
  end
end
