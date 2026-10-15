# 出库改由财务审核「款收齐没有」。
#
# 用户给的金蝶流程：业务下销售订单 → 主管审核 → 推到仓库 → **财务审核是否收齐全款** → 出库。
# 主管那道已经在销售订单上（Crm::SalesOrderApproval），出库这道换成财务。
#
# approve_note：款没收齐时财务仍可放行（老客户赊账、老板特批），但必须写理由留痕。
# 生产上 28 张生产出库全是 SHIPPED、现货只有 1 张草稿，没有会被卡住的存量单。
class AddFinanceApprovalToMesShipments < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_shipments, :approve_note, :text
  end
end
