# 生产订单上的物料反馈：采购写、业务看。
#
# 用户原话：「加一个反馈面板，比如这款机器什么物料延误了交期，采购在这里更新给业务看。」
# 与 BOM 行上的卡点（Mes::BomItem#blocker_kind）分工明确：
#   卡点   = 这颗料为什么**还没下采购单**（等客户确认 / 等文件 / 打样中…），责任人多半不是采购
#   本表   = 单**下出去之后**供应商那边的情况（延误 / 改期 / 缺货 / 到货），责任人是采购
# 业务不用再追着采购问「那颗料到底什么时候到」，照着这里跟客户解释就行。
# == Schema Information
#
# Table name: mes_order_feedbacks
#
#  id                  :bigint           not null, primary key
#  body                :text             not null
#  kind                :string           default("DELAY"), not null
#  material_name       :string
#  promised_date       :date
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  production_order_id :bigint           not null
#  user_id             :bigint
#
# Indexes
#
#  index_mes_order_feedbacks_on_account_id      (account_id)
#  index_mes_order_feedbacks_on_order_and_time  (production_order_id,created_at)
#
class Mes::OrderFeedback < ApplicationRecord
  KIND_LABELS = {
    'DELAY' => '交期延误',
    'RESCHEDULE' => '改期',
    'SHORTAGE' => '供应商缺货',
    'ARRIVED' => '已到货',
    'OTHER' => '其它'
  }.freeze
  KINDS = KIND_LABELS.keys.freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder'
  belongs_to :user, optional: true

  validates :body, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def kind_label = KIND_LABELS[kind]
end
