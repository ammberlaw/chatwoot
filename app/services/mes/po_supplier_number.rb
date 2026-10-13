# 供应商在一张采购单里的专属采购订单号：PU-20260928-04-01。
#
# 为什么要有：一张采购单可以含多家供应商（明细行各挂各的），原先大家共用一个 po_no——
# 供应商交货写这个号、仓库按这个号入库、财务按这个号对账，三头对不上。
#
# 号一旦发出去就不能再变，所以序号存在明细行上（supplier_seq），不在渲染时按顺序算：
# 往单里加一家供应商，不会把已经发出去的那几家的号冲掉。单一供应商的单也带 -01，
# 道理一样——今天只有一家，明天加一家就不至于把第一家的号改掉。
class Mes::PoSupplierNumber
  def self.for(purchase_order, supplier_id)
    seq = purchase_order.purchase_items.find { |i| i.mes_supplier_id == supplier_id }&.supplier_seq
    seq ? format('%<po>s-%<seq>02d', po: purchase_order.po_no, seq: seq) : purchase_order.po_no
  end

  # 给本单里还没有号的供应商定序号；已经有号的一概不动。
  # 「未指定供应商」（supplier_id 为 nil）也占一个号——导出时它自成一份单。
  def self.assign!(purchase_order)
    groups = purchase_order.purchase_items.reload.group_by(&:mes_supplier_id)
    next_seq = groups.values.flatten.filter_map(&:supplier_seq).max.to_i
    groups.each_value do |items|
      existing = items.filter_map(&:supplier_seq).min
      next_seq += 1 unless existing
      stamp(items, existing || next_seq)
    end
  end

  def self.stamp(items, seq)
    stale = items.reject { |i| i.supplier_seq == seq }
    return if stale.empty?

    # update_all：这是建号不是业务改单，不必再跑一遍明细校验，也避免回调套回调。
    Mes::PurchaseItem.where(id: stale.map(&:id)).update_all(supplier_seq: seq) # rubocop:disable Rails/SkipsModelValidations
  end
  private_class_method :stamp
end
