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
  KINDS = %w[
    approval_pending approval_approved approval_rejected
    bom_reconfirm bom_confirmed stage_assigned stage_returned
  ].freeze

  belongs_to :account
  belongs_to :recipient, class_name: 'User'
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :for_recipient, ->(uid) { where(recipient_id: uid) }
  scope :recent_first, -> { order(created_at: :desc) }

  def read? = read_at.present?
end
