# 生产订单阶段到达事件：每进入一个阶段记一条（阶段+到达时间+操作人），供进度条时间线。
class Mes::ProductionOrderStageEvent < ApplicationRecord
  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', inverse_of: :stage_events
  belongs_to :actor, class_name: 'User', optional: true
end
