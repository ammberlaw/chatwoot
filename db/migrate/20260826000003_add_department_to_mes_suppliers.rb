class AddDepartmentToMesSuppliers < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_suppliers, :department, :string
  end
end
