# 原料入库单加一道财务审核：审核通过才能过账（过账会刷库存、起应付，所以闸设在过账前）。
#
# 只对原料入库生效，成品入库（车间开单→仓库清点→直接过账）那条线不动，
# 所以存量单一律按「已通过」回填，不然仓库手里几十张老单会突然全部过不了账。
class AddApprovalToMesStockEntries < ActiveRecord::Migration[7.0]
  def up
    add_column :mes_stock_entries, :approval_status, :string, null: false, default: 'APPROVED'
    add_column :mes_stock_entries, :approved_at, :datetime
    add_column :mes_stock_entries, :approved_by_id, :bigint
    add_column :mes_stock_entries, :reject_reason, :text
    add_index :mes_stock_entries, [:account_id, :approval_status],
              name: 'index_mes_stock_entries_on_account_and_approval'
  end

  def down
    remove_index :mes_stock_entries, name: 'index_mes_stock_entries_on_account_and_approval'
    remove_column :mes_stock_entries, :approval_status
    remove_column :mes_stock_entries, :approved_at
    remove_column :mes_stock_entries, :approved_by_id
    remove_column :mes_stock_entries, :reject_reason
  end
end
