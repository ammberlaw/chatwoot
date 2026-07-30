# 单据级「退回上一环节」能力（横切各操作单据：采购/入库/领料/报工…）。
#
# 语义：下游拿到上游交接的单据，发现上游有问题（如供应商没货要换、料不对），
# 一键退回上一环节并留原因；系统给上游板块负责人推站内通知，但**不自动改动任何下游数据**——
# 上游收到后自行处置（改 BOM/物料，或原样退回让下游继续），责任明确回上游。
#
# 与生产订单阶段级 reject_to_previous!（回退整张订单的 stage）相互独立：本机制只标记单据、不动阶段。
#
# 各 include 的模型须实现：
#   - document_board_key   本单据所属板块 key（StockEntry 按 purpose 而不同）
#   - return_document_label 中文单据名（用于通知文案）
#   - return_document_no    单据号（用于通知文案）
#   - returnable?           当前状态是否允许退回（已过账/已完成的单不可退）
module Mes::Returnable
  extend ActiveSupport::Concern

  # 板块链（顺序即上下游）：退回目标 = 本单据板块在链上的「上一环节」。
  RETURN_CHAIN = %w[
    mes_boms_index
    mes_purchase_orders_index
    mes_stock_entries_index
    mes_material_issues_index
    mes_production_records_index
    mes_fg_inbound_index
  ].freeze

  included do
    has_many :document_returns, as: :returnable, class_name: 'Mes::DocumentReturn', dependent: :destroy
  end

  # 当前未解决的退回（存在=已退回状态）。
  def active_return
    document_returns.active.order(created_at: :desc).first
  end

  def returned?
    active_return.present?
  end

  # 退回上一环节：记录 + 通知上游板块负责人。
  def return_to_upstream!(actor:, reason:)
    raise StandardError, '该单据当前状态不可退回' unless returnable?
    raise StandardError, '单据已处于退回状态，无需重复退回' if returned?

    upstream = upstream_board_key
    raise StandardError, '已是最上游环节，无法再退回' if upstream.blank?

    ret = document_returns.create!(
      account_id: account_id, returned_by_id: actor&.id, reason: reason,
      from_board_key: document_board_key, to_board_key: upstream
    )
    notify_return_upstream(upstream, ret)
    ret
  end

  # 上游处理完/重新激活：解决当前退回（保留历史留痕）。
  def reactivate!(actor:)
    ret = active_return
    raise StandardError, '当前单据不在退回状态' if ret.blank?

    ret.update!(resolved_at: Time.current, resolved_by_id: actor&.id)
    ret
  end

  private

  def upstream_board_key
    idx = RETURN_CHAIN.index(document_board_key)
    idx&.positive? ? RETURN_CHAIN[idx - 1] : nil
  end

  def notify_return_upstream(board_key, ret)
    recipients = account.mes_board_owners.find_by(board_key: board_key)&.manager_ids || []
    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'document_returned',
      title: "#{return_document_label}被退回：#{return_document_no}",
      body: "#{return_document_label} #{return_document_no} 被下游退回，原因：#{ret.reason}",
      order: try(:production_order)
    )
  end
end
