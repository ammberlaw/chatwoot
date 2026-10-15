# 销售订单审核：审核通过才能转生产订单、才进财务「待建账」。
#
# 用户原话：「现在 crm 的销售订单转 mes 或 erp 时需要被审核才可以推送」。
#
# ⚠️ default 'APPROVED'：存量订单一次性放行。生产上几百张在跑的单如果默认落到待审核，
# 第二天业务全部转不了单、财务全部建不了账（入库审核那次就是这么处理的）。
# 闸只对这之后新建的单生效。
class AddApprovalToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    change_table :crm_sales_orders, bulk: true do |t|
      t.string :approval_status, null: false, default: 'APPROVED'
      t.bigint :approved_by_id
      t.datetime :approved_at
      t.text :reject_reason
    end
    add_index :crm_sales_orders, %i[account_id approval_status]
  end
end
