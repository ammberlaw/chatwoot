# 生产订单「知会/转发」留痕：业务把订单转发给某阶段负责人时记一条，订单详情按时间倒序回看。
# 收件人姓名做快照存字段，不实时 join——即使日后负责人变动，也保留当时知会了谁。
# == Schema Information
#
# Table name: mes_order_forwards
#
#  id                  :bigint           not null, primary key
#  board_key           :string           not null
#  note                :text
#  recipient_names     :string
#  stage_label         :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  production_order_id :bigint           not null
#  sender_id           :bigint           not null
#
# Indexes
#
#  index_mes_order_forwards_on_account_id_and_production_order_id  (account_id,production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => cascade
#
class Mes::OrderForward < ApplicationRecord
  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder'
  belongs_to :sender, class_name: 'User'

  validates :board_key, presence: true
end
