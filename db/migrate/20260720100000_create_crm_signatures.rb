class CreateCrmSignatures < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_signatures do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false

      t.timestamps
    end
    add_index :crm_signatures, %i[account_id user_id], unique: true
    add_foreign_key :crm_signatures, :accounts, column: :account_id, on_delete: :cascade
    add_foreign_key :crm_signatures, :users, column: :user_id, on_delete: :cascade
  end
end
