class CreateCrmMemberInvites < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_member_invites do |t|
      t.bigint :account_id, null: false, index: true
      t.string :token, null: false, index: { unique: true }
      t.string :system_role, null: false, default: 'sales'
      t.text :module_access, array: true, null: false, default: %w[crm erp mes]
      t.bigint :department_id
      t.string :note
      t.bigint :created_by_id
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.bigint :used_by_id

      t.timestamps
    end
  end
end
