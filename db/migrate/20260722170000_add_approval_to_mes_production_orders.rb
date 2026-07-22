class AddApprovalToMesProductionOrders < ActiveRecord::Migration[7.1]
  def up
    change_table :mes_production_orders, bulk: true do |t|
      t.string :pi_no                          # PI 编号（形式发票号）
      t.string :approval_status, null: false, default: 'DRAFT'
      t.bigint :manager_id                     # 部门主管（提交时按组织架构解析）
      t.bigint :gm_id                          # 总经理（绩效设置指定）
      t.datetime :submitted_at
      t.datetime :manager_acted_at
      t.text :manager_comment
      t.datetime :gm_acted_at
      t.text :gm_comment
    end
    add_index :mes_production_orders, [:account_id, :approval_status]
    add_index :mes_production_orders, :manager_id
    add_index :mes_production_orders, :gm_id

    # 存量回填：已发布→APPROVED；草稿→DRAFT。
    execute("UPDATE mes_production_orders SET approval_status = CASE WHEN is_draft THEN 'DRAFT' ELSE 'APPROVED' END")
  end

  def down
    remove_index :mes_production_orders, column: [:account_id, :approval_status]
    remove_index :mes_production_orders, column: :manager_id
    remove_index :mes_production_orders, column: :gm_id
    change_table :mes_production_orders, bulk: true do |t|
      t.remove :pi_no, :approval_status, :manager_id, :gm_id, :submitted_at,
               :manager_acted_at, :manager_comment, :gm_acted_at, :gm_comment
    end
  end
end
