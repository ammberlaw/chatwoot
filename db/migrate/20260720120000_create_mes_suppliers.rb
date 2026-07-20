class CreateMesSuppliers < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_suppliers do |t|
      t.references :account, null: false, index: true
      t.string :supplier_no, null: false
      t.string :name, null: false
      t.string :contact_name
      t.string :phone
      t.string :email
      t.text :address
      t.bigint :owner_id, index: true
      t.boolean :is_active, default: true, null: false
      t.text :remark
      t.timestamps
    end

    add_index :mes_suppliers, [:account_id, :supplier_no], unique: true
    add_foreign_key :mes_suppliers, :users, column: :owner_id, on_delete: :nullify
  end
end
