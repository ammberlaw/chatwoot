class CreateMesDocumentReturns < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_document_returns do |t|
      t.references :account, null: false, foreign_key: true
      t.references :returnable, polymorphic: true, null: false
      t.bigint :returned_by_id
      t.text :reason, null: false
      t.string :from_board_key
      t.string :to_board_key, null: false
      t.datetime :resolved_at
      t.bigint :resolved_by_id

      t.timestamps
    end

    # 一张单据「当前是否处于退回中」= 存在未解决(resolved_at 为空)的退回行。
    add_index :mes_document_returns,
              [:returnable_type, :returnable_id, :resolved_at],
              name: 'index_mes_document_returns_on_returnable_and_resolved'
  end
end
