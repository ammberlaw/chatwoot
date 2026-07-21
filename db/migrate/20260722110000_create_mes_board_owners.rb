class CreateMesBoardOwners < ActiveRecord::Migration[7.1]
  # 每个 MES 阶段板块（按前端路由名 board_key）配负责人（可多人），业务据此知道各阶段找谁。
  def change
    create_table :mes_board_owners do |t|
      t.references :account, null: false, foreign_key: true
      t.string :board_key, null: false
      t.bigint :manager_ids, array: true, null: false, default: []
      t.timestamps
    end
    add_index :mes_board_owners, [:account_id, :board_key], unique: true
  end
end
