class CreateTiktokDepartments < ActiveRecord::Migration[7.1]
  def change
    create_table :tiktok_departments do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false           # 部门名（如 菲律宾一组）
      t.bigint :leader_id                    # 负责人（users.id）
      t.timestamps
    end

    add_index :tiktok_departments, %i[account_id name], unique: true, name: 'idx_tiktok_departments_name'
    add_index :tiktok_departments, :leader_id
    add_foreign_key :tiktok_departments, :accounts, column: :account_id, on_delete: :cascade
    add_foreign_key :tiktok_departments, :users, column: :leader_id, on_delete: :nullify
  end
end
