class CreateCrmExhibitionInvites < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_exhibition_invites do |t|
      t.references :account, null: false, foreign_key: true
      t.references :crm_exhibition, null: false, foreign_key: { on_delete: :cascade }
      t.references :crm_customer, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :owner_id

      t.string :stage, null: false, default: 'pending'
      t.string :match_level

      t.datetime :invited_at
      t.datetime :interacted_at
      t.datetime :accepted_at
      t.datetime :declined_at

      t.string :confirm_token, null: false

      # 落地页回填（客户在线确认到访时填写）
      t.string :reply_company
      t.string :reply_name
      t.string :reply_contact
      t.string :reply_products
      t.date :reply_visit_date
      t.text :reply_note

      t.timestamps
    end

    add_index :crm_exhibition_invites, [:crm_exhibition_id, :crm_customer_id], unique: true, name: 'idx_crm_exhibition_invites_uniq'
    add_index :crm_exhibition_invites, :confirm_token, unique: true
    add_index :crm_exhibition_invites, :owner_id
    add_index :crm_exhibition_invites, [:crm_exhibition_id, :stage]
  end
end
