class AddGroupCodeToCrmProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_products, :group_code, :string
    add_index :crm_products, [:account_id, :group_code]
  end
end
