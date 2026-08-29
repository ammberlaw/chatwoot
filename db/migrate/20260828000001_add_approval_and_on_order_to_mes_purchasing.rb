class AddApprovalAndOnOrderToMesPurchasing < ActiveRecord::Migration[7.1]
  def change
    # 采购单总经理一级审批链（与收货状态 status 正交）。
    add_column :mes_purchase_orders, :approval_status, :string, null: false, default: 'DRAFT'
    add_column :mes_purchase_orders, :submitted_at, :datetime
    add_column :mes_purchase_orders, :gm_id, :bigint
    add_column :mes_purchase_orders, :gm_acted_at, :datetime
    add_column :mes_purchase_orders, :gm_comment, :text
    add_index :mes_purchase_orders, [:account_id, :approval_status]
    add_index :mes_purchase_orders, :gm_id
    add_foreign_key :mes_purchase_orders, :users, column: :gm_id, on_delete: :nullify

    # 采购明细含税/未税标记：录入单价代表含税价还是未税价。
    add_column :mes_purchase_items, :price_tax_included, :boolean, null: false, default: false

    # 库存结存在途量（已订购未到货）：采购审批通过累加、到货冲减。
    add_column :mes_stock_balances, :on_order_qty, :decimal, precision: 16, scale: 3, null: false, default: 0
  end
end
