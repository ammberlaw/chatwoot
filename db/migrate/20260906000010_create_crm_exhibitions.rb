class CreateCrmExhibitions < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_exhibitions do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :account_owner_id

      t.string :name, null: false
      t.string :country
      t.string :region
      t.string :city
      t.string :venue
      t.string :hall
      t.string :booth_no
      t.string :website

      t.date :starts_on
      t.date :ends_on

      t.text :featured_products
      t.text :theme

      t.string :status, null: false, default: 'active'

      t.timestamps
    end

    add_index :crm_exhibitions, :account_owner_id
    add_index :crm_exhibitions, [:account_id, :status]
  end
end
