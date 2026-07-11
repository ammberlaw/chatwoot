class AddAddressAndLinkedinToCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_customers, :address, :string
    add_column :crm_customers, :linkedin, :string
  end
end
