# 生产订单阶段到达事件：每进入一个阶段记一条（阶段+到达时间+操作人），供进度条时间线。
# == Schema Information
#
# Table name: mes_production_order_stage_events
#
#  id                  :bigint           not null, primary key
#  entered_at          :datetime         not null
#  note                :text
#  stage               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  actor_id            :bigint
#  production_order_id :bigint           not null
#
# Indexes
#
#  index_mes_po_stage_events_unique                                (production_order_id,stage) UNIQUE
#  index_mes_production_order_stage_events_on_account_id           (account_id)
#  index_mes_production_order_stage_events_on_production_order_id  (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => cascade
#
class Mes::ProductionOrderStageEvent < ApplicationRecord
  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', inverse_of: :stage_events
  belongs_to :actor, class_name: 'User', optional: true
end
