# 审批留痕：记下「实际点按钮的人」。
#
# 原先 gm_approve!/reject_approval! 直接把 gm_id/manager_id 改成操作人，
# 管理员代批时会把指定审批人的名字顶掉，事后看不出这单是谁代的。
# 指定审批人（manager_id/gm_id）从此只由提交时解析决定，不再被审批动作覆盖。
class AddApprovalActorsToMesProductionOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_production_orders, :manager_acted_by_id, :bigint
    add_column :mes_production_orders, :gm_acted_by_id, :bigint
  end
end
