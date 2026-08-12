class AddDepartmentToTiktokShops < ActiveRecord::Migration[7.1]
  def change
    add_column :tiktok_shops, :department_id, :bigint
    add_index :tiktok_shops, :department_id
    add_foreign_key :tiktok_shops, :tiktok_departments, column: :department_id, on_delete: :nullify
  end
end
