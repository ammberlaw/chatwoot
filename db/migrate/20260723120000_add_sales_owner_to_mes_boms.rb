class AddSalesOwnerToMesBoms < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_boms, :sales_owner_id, :bigint
    add_index :mes_boms, :sales_owner_id
    add_foreign_key :mes_boms, :users, column: :sales_owner_id, on_delete: :nullify
  end
end
