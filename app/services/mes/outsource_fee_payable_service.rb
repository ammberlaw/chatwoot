# 委外加工费 → 应付账款。
#
# 一张委外加工单一条应付，金额按**已入库数量**累计（分批入库就跟着往上加），
# 不是建单时就把整单加工费挂上去——货没回来不欠钱。
#
# 金额用含税价：应付记的是实际要付给加工厂的钱（金蝶那张单上的「含税加工费单价」）。
# 未税价留在加工单上给成本侧用。
#
# ⚠️ 不挂在入库过账里：2026-10-21 财务定的流程是**先跟加工厂对账、对好了再建账**，
# 采购收货那条路已经停掉自动建账（见 Mes::StockEntry#post! 的注释）。这里同口径——
# 由人在加工单上点「生成加工费」才建，和金蝶那张入库单上的同名按钮对应。
class Mes::OutsourceFeePayableService
  def initialize(order)
    @order = order
    @account = order.account
  end

  def sync!
    received = @order.received_qty.to_d
    amount = (received * @order.fee_rate_taxed_micros).round
    payable = find_payable
    return create_payable(amount) if payable.nil?
    # 入库全作废了（已收归零）：应付跟着归零，但已付过款的不动——那要财务自己去核销。
    return payable if amount < payable.paid_amount_micros.to_i

    payable.update!(total_amount_micros: amount, incurred_on: payable.incurred_on || last_receipt_date)
    payable.update!(status: payable.derived_status)
    payable
  end

  private

  def find_payable
    @account.erp_payables.find_by(mes_outsource_order_id: @order.id)
  end

  def create_payable(amount)
    @account.erp_payables.create!(
      mes_outsource_order_id: @order.id,
      mes_supplier_id: @order.mes_supplier_id,
      total_amount_micros: amount,
      incurred_on: last_receipt_date,
      remark: "委外加工单 #{@order.order_no} 加工费"
    )
  end

  # 发生日期＝最后一次产品入库过账那天，财务按它分月。
  def last_receipt_date
    @account.mes_stock_entries.posted
            .where(outsource_order_id: @order.id, purpose: 'OUTSOURCE_RECEIPT')
            .maximum(:posted_at)&.to_date
  end
end
