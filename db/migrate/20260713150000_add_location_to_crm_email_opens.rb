class AddLocationToCrmEmailOpens < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_email_opens, :country, :string
    add_column :crm_email_opens, :city, :string
  end
end
