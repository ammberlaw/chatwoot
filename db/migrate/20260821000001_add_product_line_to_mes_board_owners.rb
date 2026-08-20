# 阶段负责人按产品线分：加 product_line 维度（''=全部产线，作为未分线的通用/回落负责人）。
# 唯一键从 (account, board_key) 改为 (account, board_key, product_line)，同一阶段每条产品线各配一份。
class AddProductLineToMesBoardOwners < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_board_owners, :product_line, :string, null: false, default: ''
    remove_index :mes_board_owners, name: 'index_mes_board_owners_on_account_id_and_board_key'
    add_index :mes_board_owners, [:account_id, :board_key, :product_line],
              unique: true, name: 'index_mes_board_owners_on_account_board_line'
  end
end
