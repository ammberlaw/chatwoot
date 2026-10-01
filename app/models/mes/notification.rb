# == Schema Information
#
# Table name: mes_notifications
#
#  id                  :bigint           not null, primary key
#  body                :text
#  kind                :string           not null
#  read_at             :datetime
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  production_order_id :bigint
#  recipient_id        :bigint           not null
#
# Indexes
#
#  idx_on_account_id_recipient_id_read_at_4123636370  (account_id,recipient_id,read_at)
#  index_mes_notifications_on_account_id              (account_id)
#  index_mes_notifications_on_production_order_id     (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => cascade
#  fk_rails_...  (recipient_id => users.id) ON DELETE => cascade
#
# MES 站内通知（生产流转 / 审批 / 接单待办）。与 Chatwoot 会话通知体系相互独立，
# 只服务生产管理板块；持久化便于未读角标与历史，另经 ActionCable 实时下发。
class Mes::Notification < ApplicationRecord
  # 通知类型。前端据此上色/跳转。
  # approval_approved / po_approval_approved 不再产生新通知（通过了没人需要动手，
  # 只会把待办挤下去）——常量保留，历史记录还按它归类。
  KINDS = %w[
    approval_pending approval_approved approval_rejected
    bom_reconfirm bom_confirmed bom_revised purchase_release_pending stage_assigned stage_returned
    po_approval_pending po_approval_approved po_approval_rejected
    order_revised
    production_reported fg_count_pending
    shipment_approval_pending shipment_approved shipment_rejected
    document_returned
    forwarded
    erp_installment_due erp_payable_due erp_expense_paid
  ].freeze

  # ERP（财务）复用本表发通知，但它们不该混进 MES 的站内通知——
  # 生产端打开站内通知看到一屏「应付已逾期」，真正的待接单/待审批被挤下去了。
  # 两边按模块各看各的。
  ERP_KINDS = %w[erp_installment_due erp_payable_due erp_expense_paid].freeze

  belongs_to :account
  belongs_to :recipient, class_name: 'User'
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :for_recipient, ->(uid) { where(recipient_id: uid) }
  # id 兜底：批量写入的通知 created_at 常常同一毫秒，只按时间排翻页会漏条/重条。
  scope :for_module, ->(mod) { mod.to_s == 'erp' ? where(kind: ERP_KINDS) : where.not(kind: ERP_KINDS) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def read? = read_at.present?
end
