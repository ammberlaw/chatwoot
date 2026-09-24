# 阶段接单/转交流水（见迁移说明）：一个阶段允许两个人接力，各自留痕。
class Mes::StageAckEvent < ApplicationRecord
  ACK = 'ACK'
  HANDOFF = 'HANDOFF'
  KINDS = [ACK, HANDOFF].freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', inverse_of: :stage_ack_events
  belongs_to :actor, class_name: 'User'
  belongs_to :to_user, class_name: 'User', optional: true

  validates :stage, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :chronological, -> { order(:happened_at, :id) }
end
