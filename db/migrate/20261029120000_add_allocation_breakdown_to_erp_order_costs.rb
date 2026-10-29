# 月末按实际发生额分摊出来的制造费用，按月份存一份明细。
#
# 解决两件事：
#
# ① 两个写入方抢同一行。erp_order_costs 对 (source_type, source_id, cost_type) 是唯一索引，
#    而制造费用有两个来源：
#      Erp::CostRollupService        入库/出货即写，= 完工数量 × BOM 成本表标准单价（估数）
#      Erp::OverheadAllocationService 月末才写，   = 当月 5101 实际发生额按完工量摊（实际数）
#    没有标记时财务月末摊完，订单再出一次货就被估数打回去；而生产上 161 条 BOM 成本的
#    制造费用标准值全是 0，归集算出 0 会走「金额≤0 就删行」那一支，整行直接没了。
#    本列非空＝这行是摊出来的，归集绕开它：估数不该盖实际数。
#
# ② 跨月完工的订单。一张生产订单分两批入库（9 月 300 台、10 月 800 台）时，原来摊完
#    10 月会把 9 月那笔覆盖掉，订单只吸收最后一个月的费用。按月份存明细后
#    amount_micros = 各月之和，重摊某个月只替换该月那一项。
#
# 形状：{"2026-10" => {"amount_micros" => 40000000000, "qty" => "800"}}
class AddAllocationBreakdownToErpOrderCosts < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_order_costs, :allocation_breakdown, :jsonb
  end
end
