class AddStatusToMesBoms < ActiveRecord::Migration[7.1]
  # 工程/PMC BOM 草稿/下发：草稿可反复编辑、对下游隐藏；下发后才可被生产订单挂用。
  def up
    add_column :mes_boms, :status, :string, null: false, default: 'DRAFT'
    add_index :mes_boms, [:account_id, :status]
    # 存量 BOM 视为已下发（此前建即可用）。
    execute("UPDATE mes_boms SET status = 'RELEASED'")
  end

  def down
    remove_column :mes_boms, :status
  end
end
