class CreateMesBomRevisions < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_bom_revisions do |t|
      t.references :account, null: false, index: true
      t.references :bom, null: false, foreign_key: { to_table: :mes_boms, on_delete: :cascade }, index: true
      t.integer :rev_no, null: false
      t.bigint :changed_by_id
      t.text :reason
      t.jsonb :diff, null: false, default: []
      t.timestamps
    end

    add_index :mes_bom_revisions, [:account_id, :bom_id]
    add_foreign_key :mes_bom_revisions, :users, column: :changed_by_id, on_delete: :nullify
  end
end
