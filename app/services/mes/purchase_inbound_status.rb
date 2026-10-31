# 采购单的入库状态与入库时间。
#
# 采购员在采购单上确认「已到货」，仓管在原料入库单上过账——两件事两张单，
# 采购单列表上一直只看得到前者。2026-10-30 的反馈原话：
# 「入库状态入库时间：由仓管原材料入库后同步已入库和入库时间。」
#
# 一张入库单可能同时冲抵多张采购单（同款物料几张单一起收），所以除了
# purchase_order_id 还要认 extra_purchase_order_ids 这个数组列（生产上 32 张这么挂的）。
# 只认**已过账**的入库单：草稿态的入库单还没真进库存，报「已入库」会骗人。
class Mes::PurchaseInboundStatus
  def initialize(account)
    @account = account
  end

  # { 采购单id => { posted_at:, entries: } }；没入库过的 id 不出现在结果里。
  def for_ids(po_ids)
    ids = Array(po_ids).compact.uniq
    return {} if ids.empty?

    rows(ids).each_with_object({}) do |entry, acc|
      target_ids(entry, ids).each do |po_id|
        cur = acc[po_id] ||= { posted_at: nil, entries: 0 }
        cur[:entries] += 1
        cur[:posted_at] = entry.posted_at if cur[:posted_at].nil? || entry.posted_at > cur[:posted_at]
      end
    end
  end

  private

  def rows(ids)
    @account.mes_stock_entries
            .where.not(posted_at: nil)
            .where('purchase_order_id IN (:ids) OR extra_purchase_order_ids && ARRAY[:ids]::bigint[]', ids: ids)
            .select(:id, :purchase_order_id, :extra_purchase_order_ids, :posted_at)
  end

  # 这张入库单冲抵了本页哪几张采购单（主挂 + 额外挂，都要落在本次查询的 id 里）。
  def target_ids(entry, ids)
    ([entry.purchase_order_id] + Array(entry.extra_purchase_order_ids)).compact.uniq & ids
  end
end
