# 采购单的「关闭 / 启用 / 删除」。
#
# 原来只有单向的「取消」：点错一次这张单就废了，今天不下、明天还要下只能重开一张，
# 而且关掉之后审批队列里照样挂着「待审批」。改成一对可逆动作（口径对齐金蝶）：
#   关闭 = 这单先不采购了——回冲未收货在途，待审批的从审批队列撤下来
#   启用 = 接着用——收货状态退回草稿，已批过的保留审批结果、在途重新挂上
#
# 状态码仍沿用 CANCELLED，不动存量数据与下游判断（齐套、在途、退回都已经按它写了）。
module Mes::PurchaseOrderClosing
  extend ActiveSupport::Concern

  def closed? = status == 'CANCELLED'

  # 可删：还没进流程的草稿（未提审、未到货），以及已关闭的单。
  # 已提交/已批但还开着的单一律留痕，走「退回」而不是删；关闭过的单在途已经冲回、
  # 关闭本身就是一次留痕动作，采购确定不要了就该能自己清掉。
  def deletable?
    return false if received_any?

    closed? || (status == 'DRAFT' && approval_status.in?(%w[DRAFT REJECTED]))
  end

  def close!
    raise StandardError, '这张单已经收过货，不能关闭——请走退回' if received_any?
    raise StandardError, '这张单已经关闭了' if closed?

    withdrawing = pending_approval?
    attrs = { status: 'CANCELLED' }
    attrs.merge!(approval_status: 'DRAFT', gm_acted_at: nil, gm_comment: nil) if withdrawing
    # 在途由 before_update release_on_order_on_cancel 回冲（只有已批的单加过在途）。
    update!(attrs)
    Mes::Notifier.resolve(account: account, kinds: 'po_approval_pending', title_like: po_no) if withdrawing
    self
  end

  def reopen!
    raise StandardError, '这张单没有关闭' unless closed?

    transaction do
      update!(status: 'DRAFT')
      apply_on_order!(1) if approved?
    end
    self
  end

  private

  def received_any? = purchase_items.where('received_qty > 0').any?
end
