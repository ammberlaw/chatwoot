# PI 挂商机：商机阶段要跟着单据自动走（做了 PI＝待付款、收款＝已成交），
# 而 PI 是这条链上唯一还没有商机外键的单据（报价单和销售订单早就有了）。
#
# 为什么非挂不可：生产 610 张销售订单里只有 33 张挂着商机（5.4%），
# 而 607 张有 PI 号——PI 才是真实业务流的枢纽，不从这儿接，自动推进覆盖不到任何单子。
class AddOpportunityToCrmPis < ActiveRecord::Migration[7.1]
  def change
    add_reference :crm_pis, :crm_opportunity, null: true, index: true
  end
end
