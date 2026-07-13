class CreateOrgStructure < ActiveRecord::Migration[7.1]
  def change
    create_table :org_departments do |t|
      t.bigint :account_id, null: false, index: true
      t.bigint :parent_id
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.bigint :leader_id, index: true
      t.timestamps
      t.index [:account_id, :parent_id]
    end

    create_table :org_memberships do |t|
      t.bigint :account_id, null: false, index: true
      t.references :department, null: false, foreign_key: { to_table: :org_departments, on_delete: :cascade }
      t.bigint :user_id, null: false, index: true
      t.string :title
      t.boolean :is_primary, default: false, null: false
      t.timestamps
      t.index [:department_id, :user_id], unique: true, name: 'index_org_memberships_unique'
    end
  end
end
