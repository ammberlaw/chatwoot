# 阶段接单/转交流水（见迁移说明）：一个阶段允许两个人接力，各自留痕。
# == Schema Information
#
# Table name: mes_stage_ack_events
#
#  id                  :bigint           not null, primary key
#  happened_at         :datetime         not null
#  kind                :string           not null
#  note                :text
#  stage               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  actor_id            :bigint           not null
#  production_order_id :bigint           not null
#  to_user_id          :bigint
#
# Indexes
#
#  idx_mes_stage_ack_events_lookup    (account_id,production_order_id,happened_at)
#  idx_mes_stage_ack_events_on_order  (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (actor_id => users.id) ON DELETE => cascade
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => cascade
#  fk_rails_...  (to_user_id => users.id) ON DELETE => nullify
#
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
